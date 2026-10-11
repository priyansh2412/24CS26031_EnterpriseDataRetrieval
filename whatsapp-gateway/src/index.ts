import dotenv from 'dotenv';
dotenv.config();

import pino from 'pino';
import qrcode from 'qrcode-terminal';
import makeWASocketPkg, {
  DisconnectReason,
  fetchLatestBaileysVersion,
  useMultiFileAuthState,
  type WAMessage,
  type proto,
} from '@whiskeysockets/baileys';

// Handle default export compatibility for ESM / CJS interop
const makeWASocket =
  (makeWASocketPkg as unknown as { default?: typeof makeWASocketPkg }).default ||
  makeWASocketPkg;

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
});

const baileysLogger = pino({
  level: 'warn',
});

// Process-level crash guards
process.on('unhandledRejection', (reason) => {
  logger.error({ reason }, 'Unhandled Rejection caught');
});

process.on('uncaughtException', (err) => {
  logger.error({ err }, 'Uncaught Exception caught');
});

const API_URL = process.env.API_URL || 'http://127.0.0.1:8000';
const GATEWAY_SECRET = process.env.GATEWAY_SECRET || '';
const ALLOW_GROUPS = process.env.ALLOW_GROUPS === 'true';

// Per-JID sequential promise queue
const jidQueues = new Map<string, Promise<void>>();

function enqueueForJid(jid: string, fn: () => Promise<void>): void {
  const currentPromise = jidQueues.get(jid) || Promise.resolve();
  const nextPromise = currentPromise
    .then(async () => {
      try {
        await fn();
      } catch (err) {
        logger.error({ err, jid }, 'Error executing queued task for JID');
      }
    })
    .finally(() => {
      if (jidQueues.get(jid) === nextPromise) {
        jidQueues.delete(jid);
      }
    });

  jidQueues.set(jid, nextPromise);
}

// Split large messages on paragraph boundaries (max 3000 chars)
export function splitMessage(text: string, maxLen = 3000): string[] {
  if (!text || text.length <= maxLen) {
    return [text];
  }

  const paragraphs = text.split(/\n\s*\n/);
  const chunks: string[] = [];
  let currentChunk = '';

  for (const paragraph of paragraphs) {
    // If a single paragraph is larger than maxLen, split it by line or chunk
    if (paragraph.length > maxLen) {
      if (currentChunk.trim().length > 0) {
        chunks.push(currentChunk.trim());
        currentChunk = '';
      }
      const lines = paragraph.split('\n');
      for (const line of lines) {
        if (line.length > maxLen) {
          if (currentChunk.trim().length > 0) {
            chunks.push(currentChunk.trim());
            currentChunk = '';
          }
          // Hard split on character boundary
          for (let i = 0; i < line.length; i += maxLen) {
            chunks.push(line.slice(i, i + maxLen));
          }
        } else if ((currentChunk ? currentChunk.length + 1 : 0) + line.length > maxLen) {
          chunks.push(currentChunk.trim());
          currentChunk = line;
        } else {
          currentChunk = currentChunk ? `${currentChunk}\n${line}` : line;
        }
      }
    } else {
      const candidate = currentChunk ? `${currentChunk}\n\n${paragraph}` : paragraph;
      if (candidate.length > maxLen) {
        if (currentChunk.trim().length > 0) {
          chunks.push(currentChunk.trim());
        }
        currentChunk = paragraph;
      } else {
        currentChunk = candidate;
      }
    }
  }

  if (currentChunk.trim().length > 0) {
    chunks.push(currentChunk.trim());
  }

  return chunks.length > 0 ? chunks : [text];
}

let reconnectDelay = 2000;
const MAX_RECONNECT_DELAY = 30000;

async function startGateway() {
  const { state, saveCreds } = await useMultiFileAuthState('./auth_state');
  const { version, isLatest } = await fetchLatestBaileysVersion();
  logger.info({ version, isLatest }, 'Starting Baileys WhatsApp Gateway');

  const sock = makeWASocket({
    version,
    auth: state,
    logger: baileysLogger as any,
    printQRInTerminal: false,
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', (update) => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      logger.info('Scan the QR code below using WhatsApp (Linked Devices):');
      qrcode.generate(qr, { small: true });
    }

    if (connection === 'close') {
      const statusCode = (lastDisconnect?.error as { output?: { statusCode?: number } })
        ?.output?.statusCode;
      const isLoggedOut = statusCode === DisconnectReason.loggedOut;

      if (isLoggedOut) {
        logger.error(
          'WhatsApp session logged out. Please delete ./auth_state and restart the gateway service.'
        );
        return;
      }

      logger.warn(
        { statusCode, reconnectDelayMs: reconnectDelay },
        `Connection closed. Reconnecting in ${reconnectDelay / 1000}s...`
      );

      setTimeout(() => {
        startGateway().catch((err) => {
          logger.error({ err }, 'Error during gateway reconnection');
        });
      }, reconnectDelay);

      reconnectDelay = Math.min(reconnectDelay * 2, MAX_RECONNECT_DELAY);
    } else if (connection === 'open') {
      reconnectDelay = 2000;
      const userId = sock.user?.id || '';
      const number = userId.split(':')[0].split('@')[0] || userId || 'unknown';
      logger.info(`Connected as ${number}`);
    }
  });

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return;

    for (const msg of messages) {
      try {
        if (!msg.key || msg.key.fromMe) continue;

        const jid = msg.key.remoteJid;
        if (!jid) continue;
        if (jid === 'status@broadcast') continue;
        if (jid.endsWith('@g.us') && !ALLOW_GROUPS) continue;

        const rawContent =
          msg.message?.ephemeralMessage?.message ||
          msg.message?.viewOnceMessage?.message ||
          msg.message;

        if (!rawContent) continue;

        // Extract text
        const text = (
          rawContent.conversation ||
          rawContent.extendedTextMessage?.text ||
          ''
        ).trim();

        const isGroup = jid.endsWith('@g.us');
        const isPrivate = !isGroup;

        // Check if message is non-text media
        const isNonTextMessage = Boolean(
          rawContent.imageMessage ||
          rawContent.videoMessage ||
          rawContent.audioMessage ||
          rawContent.documentMessage ||
          rawContent.documentWithCaptionMessage ||
          rawContent.stickerMessage ||
          rawContent.contactMessage ||
          rawContent.contactsArrayMessage ||
          rawContent.locationMessage ||
          rawContent.liveLocationMessage
        );

        if (!text) {
          if (isPrivate && isNonTextMessage) {
            enqueueForJid(jid, async () => {
              logger.info(
                { jid, messageId: msg.key.id },
                'Received non-text message in private chat; replying with text-only notice'
              );
              await sock.sendMessage(jid, {
                text: 'I can only read text messages for now.',
              });
            });
          }
          continue;
        }

        // Valid text message: process sequentially per JID
        enqueueForJid(jid, async () => {
          logger.info(
            {
              jid,
              messageId: msg.key.id,
              pushName: msg.pushName || '',
              textLength: text.length,
            },
            'Processing inbound text message'
          );

          // Mark read and indicate typing
          await sock.readMessages([msg.key]);
          await sock.sendPresenceUpdate('composing', jid);

          const controller = new AbortController();
          const timeoutId = setTimeout(() => controller.abort(), 60000);

          try {
            const response = await fetch(`${API_URL}/api/internal/whatsapp/inbound`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'x-gateway-secret': GATEWAY_SECRET,
              },
              body: JSON.stringify({
                wa_message_id: msg.key.id || `msg-${Date.now()}`,
                jid: jid,
                push_name: msg.pushName || '',
                text: text,
              }),
              signal: controller.signal,
            });

            clearTimeout(timeoutId);

            if (!response.ok) {
              const errBody = await response.text().catch(() => '');
              logger.error(
                { status: response.status, body: errBody, jid },
                'Backend returned non-OK status'
              );
              await sock.sendMessage(jid, {
                text: 'The assistant is temporarily unavailable, please try again.',
              });
              await sock.sendPresenceUpdate('paused', jid).catch(() => {});
              return;
            }

            const data = (await response.json()) as { reply?: string };
            const reply = (data?.reply || '').trim();

            if (reply.length > 0) {
              const chunks = splitMessage(reply, 3000);
              for (let i = 0; i < chunks.length; i++) {
                if (i > 0) {
                  await new Promise((resolve) => setTimeout(resolve, 600));
                }
                await sock.sendMessage(jid, { text: chunks[i] });
              }
              logger.info(
                { jid, chunksSent: chunks.length },
                'Sent assistant reply chunks to WhatsApp'
              );
            }

            await sock.sendPresenceUpdate('paused', jid).catch(() => {});
          } catch (err: unknown) {
            clearTimeout(timeoutId);
            const isAbort = (err as Error)?.name === 'AbortError';
            logger.error(
              { err, isTimeout: isAbort, jid, messageId: msg.key.id },
              'Failed to forward message to backend or send reply'
            );
            await sock.sendMessage(jid, {
              text: 'The assistant is temporarily unavailable, please try again.',
            });
            await sock.sendPresenceUpdate('paused', jid).catch(() => {});
          }
        });
      } catch (err) {
        logger.error({ err, messageKey: msg.key }, 'Error handling message upsert item');
      }
    }
  });
}

startGateway().catch((err) => {
  logger.error({ err }, 'Fatal error launching WhatsApp Gateway');
  process.exit(1);
});
