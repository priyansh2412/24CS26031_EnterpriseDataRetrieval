--
-- PostgreSQL database dump
--

\restrict srmyfiULak6NoKv9McAc2AvVO0enKIhfF7qvlsGXcMvFpuwqFlYoIQfodIXJ34e

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: app; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA app;


ALTER SCHEMA app OWNER TO postgres;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: current_tenant(); Type: FUNCTION; Schema: app; Owner: postgres
--

CREATE FUNCTION app.current_tenant() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$ SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid $$;


ALTER FUNCTION app.current_tenant() OWNER TO postgres;

--
-- Name: authorize_documents(uuid, uuid, uuid[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.authorize_documents(p_tenant uuid, p_user uuid, p_doc_ids uuid[]) RETURNS TABLE(document_id uuid)
    LANGUAGE sql STABLE
    AS $$
  WITH me AS (
    SELECT u.clearance_level, resolve_principals(p_tenant, p_user) AS principals
      FROM users u
      JOIN tenants t ON t.id = u.tenant_id AND t.status = 'active'
     WHERE u.id = p_user AND u.tenant_id = p_tenant AND u.status = 'active')
  SELECT d.id
    FROM documents d
    JOIN document_versions v ON v.id = d.current_version_id AND v.is_current AND v.status = 'approved'
    CROSS JOIN me
   WHERE d.tenant_id = p_tenant
     AND d.id = ANY (p_doc_ids)
     AND d.status = 'active'
     AND d.classification_level <= me.clearance_level
     AND EXISTS (SELECT 1 FROM document_acl_entries a
                  WHERE a.document_id = d.id AND a.effect = 'allow' AND a.permission = 'read'
                    AND a.principal_key = ANY (me.principals))
     AND NOT EXISTS (SELECT 1 FROM document_acl_entries a
                  WHERE a.document_id = d.id AND a.effect = 'deny' AND a.permission = 'read'
                    AND a.principal_key = ANY (me.principals))
$$;


ALTER FUNCTION public.authorize_documents(p_tenant uuid, p_user uuid, p_doc_ids uuid[]) OWNER TO postgres;

--
-- Name: resolve_principals(uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.resolve_principals(p_tenant uuid, p_user uuid) RETURNS text[]
    LANGUAGE sql STABLE
    AS $$
  SELECT ARRAY['t:' || p_tenant::text, 'u:' || p_user::text]
      || ARRAY(SELECT 'g:' || g.group_id::text
                 FROM user_group_closure g
                WHERE g.tenant_id = p_tenant AND g.user_id = p_user)
      || ARRAY(SELECT DISTINCT 'p:' || ra.project_id::text
                 FROM role_assignments ra
                WHERE ra.tenant_id = p_tenant AND ra.project_id IS NOT NULL
                  AND (ra.expires_at IS NULL OR ra.expires_at > now())
                  AND (ra.user_id = p_user OR ra.group_id IN
                        (SELECT group_id FROM user_group_closure
                          WHERE tenant_id = p_tenant AND user_id = p_user)))
      || ARRAY(SELECT DISTINCT 'r:' || ra.role_id::text
                 FROM role_assignments ra
                WHERE ra.tenant_id = p_tenant
                  AND (ra.expires_at IS NULL OR ra.expires_at > now())
                  AND (ra.user_id = p_user OR ra.group_id IN
                        (SELECT group_id FROM user_group_closure
                          WHERE tenant_id = p_tenant AND user_id = p_user)))
$$;


ALTER FUNCTION public.resolve_principals(p_tenant uuid, p_user uuid) OWNER TO postgres;

--
-- Name: resolve_tenant_by_slug(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.resolve_tenant_by_slug(p_slug text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$ SELECT id FROM tenants WHERE slug = p_slug AND status = 'active' $$;


ALTER FUNCTION public.resolve_tenant_by_slug(p_slug text) OWNER TO postgres;

--
-- Name: trg_audit_immutable(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_audit_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN RAISE EXCEPTION 'audit_logs is append-only'; END $$;


ALTER FUNCTION public.trg_audit_immutable() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: abac_policies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.abac_policies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    effect text NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    enforcement text NOT NULL,
    condition jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT abac_policies_effect_check CHECK ((effect = ANY (ARRAY['deny'::text, 'require'::text]))),
    CONSTRAINT abac_policies_enforcement_check CHECK ((enforcement = ANY (ARRAY['index_filter'::text, 'post_check'::text])))
);

ALTER TABLE ONLY public.abac_policies FORCE ROW LEVEL SECURITY;


ALTER TABLE public.abac_policies OWNER TO postgres;

--
-- Name: acl_outbox; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.acl_outbox (
    id bigint NOT NULL,
    tenant_id uuid,
    document_id character varying(64) NOT NULL,
    acl_version bigint NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    CONSTRAINT acl_outbox_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'done'::text, 'failed'::text])))
);

ALTER TABLE ONLY public.acl_outbox FORCE ROW LEVEL SECURITY;


ALTER TABLE public.acl_outbox OWNER TO postgres;

--
-- Name: acl_outbox_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.acl_outbox_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.acl_outbox_id_seq OWNER TO postgres;

--
-- Name: acl_outbox_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.acl_outbox_id_seq OWNED BY public.acl_outbox.id;


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    actor_type text,
    actor_user_id uuid,
    action text NOT NULL,
    resource_type text,
    resource_id text,
    outcome text,
    request_id text,
    ip inet,
    user_agent text,
    details jsonb DEFAULT '{}'::jsonb,
    prev_hash text,
    row_hash text,
    severity character varying(20) DEFAULT 'INFO'::character varying,
    user_id uuid,
    detail text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT audit_logs_actor_type_check CHECK ((actor_type = ANY (ARRAY['user'::text, 'service'::text, 'system'::text, 'admin_support'::text]))),
    CONSTRAINT audit_logs_outcome_check CHECK ((outcome = ANY (ARRAY['success'::text, 'denied'::text, 'error'::text])))
)
PARTITION BY RANGE (occurred_at);

ALTER TABLE ONLY public.audit_logs FORCE ROW LEVEL SECURITY;


ALTER TABLE public.audit_logs OWNER TO postgres;

--
-- Name: audit_logs_default; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_logs_default (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    actor_type text,
    actor_user_id uuid,
    action text NOT NULL,
    resource_type text,
    resource_id text,
    outcome text,
    request_id text,
    ip inet,
    user_agent text,
    details jsonb DEFAULT '{}'::jsonb,
    prev_hash text,
    row_hash text,
    severity character varying(20) DEFAULT 'INFO'::character varying,
    user_id uuid,
    detail text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT audit_logs_actor_type_check CHECK ((actor_type = ANY (ARRAY['user'::text, 'service'::text, 'system'::text, 'admin_support'::text]))),
    CONSTRAINT audit_logs_outcome_check CHECK ((outcome = ANY (ARRAY['success'::text, 'denied'::text, 'error'::text])))
);


ALTER TABLE public.audit_logs_default OWNER TO postgres;

--
-- Name: chunks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.chunks (
    id character varying(36) NOT NULL,
    tenant_id character varying(64),
    document_id character varying(64) NOT NULL,
    version_id character varying(36),
    project_id character varying(36),
    chunk_index integer NOT NULL,
    page_start integer,
    page_end integer,
    section_path text,
    text text NOT NULL,
    text_hash character varying(64),
    embedding_model character varying(64),
    index_state character varying(32) NOT NULL,
    created_at timestamp without time zone NOT NULL
);


ALTER TABLE public.chunks OWNER TO postgres;

--
-- Name: classification_levels; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.classification_levels (
    tenant_id uuid NOT NULL,
    level smallint NOT NULL,
    name text NOT NULL,
    CONSTRAINT classification_levels_level_check CHECK (((level >= 0) AND (level <= 9)))
);

ALTER TABLE ONLY public.classification_levels FORCE ROW LEVEL SECURITY;


ALTER TABLE public.classification_levels OWNER TO postgres;

--
-- Name: company_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_roles (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    key character varying(50) NOT NULL,
    rank_level integer DEFAULT 1,
    description text,
    permissions_json text DEFAULT '["chat", "documents:view"]'::text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.company_roles OWNER TO postgres;

--
-- Name: company_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.company_roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.company_roles_id_seq OWNER TO postgres;

--
-- Name: company_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.company_roles_id_seq OWNED BY public.company_roles.id;


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    project_id uuid,
    title text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.conversations FORCE ROW LEVEL SECURITY;


ALTER TABLE public.conversations OWNER TO postgres;

--
-- Name: document_acl_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.document_acl_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid,
    document_id character varying(64) NOT NULL,
    principal_type text,
    principal_id uuid,
    external_ref text,
    effect text DEFAULT 'allow'::text NOT NULL,
    permission text DEFAULT 'read'::text NOT NULL,
    origin text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    principal_key character varying(128),
    CONSTRAINT document_acl_entries_effect_check CHECK ((effect = ANY (ARRAY['allow'::text, 'deny'::text]))),
    CONSTRAINT document_acl_entries_origin_check CHECK ((origin = ANY (ARRAY['source_sync'::text, 'manual'::text, 'project_default'::text, 'system'::text]))),
    CONSTRAINT document_acl_entries_permission_check CHECK ((permission = 'read'::text))
);

ALTER TABLE ONLY public.document_acl_entries FORCE ROW LEVEL SECURITY;


ALTER TABLE public.document_acl_entries OWNER TO postgres;

--
-- Name: document_versions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.document_versions (
    id character varying(64) DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid,
    document_id character varying(64) NOT NULL,
    version_no integer,
    source_revision text,
    content_hash text,
    storage_key text,
    size_bytes bigint,
    status text DEFAULT 'pending'::text,
    is_current boolean DEFAULT false,
    malware_status text DEFAULT 'pending'::text,
    pii_summary jsonb DEFAULT '{}'::jsonb,
    approved_by uuid,
    approved_at timestamp with time zone,
    effective_from timestamp with time zone,
    effective_to timestamp with time zone,
    indexed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    version_number integer DEFAULT 1,
    checksum character varying(64),
    revision_id character varying(128),
    file_size bigint,
    CONSTRAINT document_versions_malware_status_check CHECK ((malware_status = ANY (ARRAY['pending'::text, 'clean'::text, 'infected'::text, 'error'::text]))),
    CONSTRAINT document_versions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'scanning'::text, 'processing'::text, 'pending_approval'::text, 'approved'::text, 'rejected'::text, 'failed'::text, 'quarantined'::text, 'superseded'::text])))
);

ALTER TABLE ONLY public.document_versions FORCE ROW LEVEL SECURITY;


ALTER TABLE public.document_versions OWNER TO postgres;

--
-- Name: documents; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.documents (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    source_hash character varying(64),
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    tenant_id character varying(64) DEFAULT 'tenant-001'::character varying,
    project_id character varying(64) DEFAULT 'project-001'::character varying,
    source character varying(50) DEFAULT 'local'::character varying,
    source_uri text,
    drive_file_id character varying(128),
    mime_type character varying(128),
    size_bytes bigint,
    owner_email character varying(255),
    web_view_link text,
    revision_id character varying(128),
    modified_time timestamp without time zone,
    checksum character varying(64),
    status character varying(32) DEFAULT 'ready'::character varying,
    summary text,
    chunk_count integer DEFAULT 0,
    acl_version integer DEFAULT 1,
    access_roles text DEFAULT '["admin", "hr", "finance", "manager", "employee"]'::text,
    denied_users text DEFAULT '[]'::text,
    folder_path character varying(512) DEFAULT '/'::character varying,
    drive_link_id integer
);


ALTER TABLE public.documents OWNER TO postgres;

--
-- Name: enterprise_admins; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.enterprise_admins (
    id integer NOT NULL,
    enterprise_name character varying(150) NOT NULL,
    admin_email character varying(255) NOT NULL,
    temp_password character varying(255) NOT NULL,
    user_id uuid,
    tenant_id character varying(64) DEFAULT 'tenant-001'::character varying,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.enterprise_admins OWNER TO postgres;

--
-- Name: enterprise_admins_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.enterprise_admins_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.enterprise_admins_id_seq OWNER TO postgres;

--
-- Name: enterprise_admins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.enterprise_admins_id_seq OWNED BY public.enterprise_admins.id;


--
-- Name: enterprise_drive_links; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.enterprise_drive_links (
    id integer NOT NULL,
    tenant_id character varying(64) NOT NULL,
    name character varying(255) NOT NULL,
    drive_url text NOT NULL,
    drive_id character varying(128),
    is_folder boolean DEFAULT true,
    password_hash character varying(255),
    status character varying(32) DEFAULT 'active'::character varying,
    doc_count integer DEFAULT 0,
    created_by_id uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.enterprise_drive_links OWNER TO postgres;

--
-- Name: enterprise_drive_links_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.enterprise_drive_links_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.enterprise_drive_links_id_seq OWNER TO postgres;

--
-- Name: enterprise_drive_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.enterprise_drive_links_id_seq OWNED BY public.enterprise_drive_links.id;


--
-- Name: external_identities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.external_identities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    source_type text NOT NULL,
    external_id text NOT NULL,
    external_email public.citext
);

ALTER TABLE ONLY public.external_identities FORCE ROW LEVEL SECURITY;


ALTER TABLE public.external_identities OWNER TO postgres;

--
-- Name: feedback; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.feedback (
    id integer NOT NULL,
    query_log_id integer,
    user_id uuid,
    is_positive boolean NOT NULL,
    comment text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.feedback OWNER TO postgres;

--
-- Name: feedback_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.feedback_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.feedback_id_seq OWNER TO postgres;

--
-- Name: feedback_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.feedback_id_seq OWNED BY public.feedback.id;


--
-- Name: group_members; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.group_members (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    group_id uuid NOT NULL,
    member_user_id uuid,
    member_group_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid,
    CONSTRAINT group_members_check CHECK (((((member_user_id IS NOT NULL))::integer + ((member_group_id IS NOT NULL))::integer) = 1)),
    CONSTRAINT group_members_check1 CHECK ((member_group_id IS DISTINCT FROM group_id))
);

ALTER TABLE ONLY public.group_members FORCE ROW LEVEL SECURITY;


ALTER TABLE public.group_members OWNER TO postgres;

--
-- Name: groups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.groups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    origin text NOT NULL,
    source_connection_id uuid,
    external_ref text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    key character varying(50),
    description text,
    CONSTRAINT groups_origin_check CHECK ((origin = ANY (ARRAY['internal'::text, 'idp'::text, 'source'::text])))
);

ALTER TABLE ONLY public.groups FORCE ROW LEVEL SECURITY;


ALTER TABLE public.groups OWNER TO postgres;

--
-- Name: identity_providers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.identity_providers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    type text NOT NULL,
    issuer text NOT NULL,
    client_id text,
    secret_ref text,
    claim_mappings jsonb DEFAULT '{}'::jsonb NOT NULL,
    jit_provisioning boolean DEFAULT true NOT NULL,
    scim_enabled boolean DEFAULT false NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT identity_providers_type_check CHECK ((type = ANY (ARRAY['oidc'::text, 'saml'::text])))
);

ALTER TABLE ONLY public.identity_providers FORCE ROW LEVEL SECURITY;


ALTER TABLE public.identity_providers OWNER TO postgres;

--
-- Name: ingestion_jobs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ingestion_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    document_version_id uuid NOT NULL,
    stage text NOT NULL,
    status text DEFAULT 'running'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    error text,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    CONSTRAINT ingestion_jobs_stage_check CHECK ((stage = ANY (ARRAY['queued'::text, 'malware_scan'::text, 'parse_ocr'::text, 'pii_detect'::text, 'metadata'::text, 'acl_extract'::text, 'chunk'::text, 'embed'::text, 'index'::text, 'done'::text]))),
    CONSTRAINT ingestion_jobs_status_check CHECK ((status = ANY (ARRAY['running'::text, 'succeeded'::text, 'failed'::text, 'retrying'::text])))
);

ALTER TABLE ONLY public.ingestion_jobs FORCE ROW LEVEL SECURITY;


ALTER TABLE public.ingestion_jobs OWNER TO postgres;

--
-- Name: message_citations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.message_citations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    message_id uuid NOT NULL,
    chunk_id uuid NOT NULL,
    document_id uuid NOT NULL,
    version_id uuid NOT NULL,
    rank integer NOT NULL,
    quote_start integer,
    quote_end integer,
    was_current_at_answer_time boolean DEFAULT true NOT NULL
);

ALTER TABLE ONLY public.message_citations FORCE ROW LEVEL SECURITY;


ALTER TABLE public.message_citations OWNER TO postgres;

--
-- Name: message_feedback; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.message_feedback (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    message_id uuid NOT NULL,
    user_id uuid NOT NULL,
    rating smallint,
    category text,
    comment text,
    status text DEFAULT 'new'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT message_feedback_category_check CHECK ((category = ANY (ARRAY['wrong'::text, 'outdated'::text, 'missing_source'::text, 'harmful'::text, 'leak_suspected'::text, 'other'::text]))),
    CONSTRAINT message_feedback_rating_check CHECK ((rating = ANY (ARRAY['-1'::integer, 1]))),
    CONSTRAINT message_feedback_status_check CHECK ((status = ANY (ARRAY['new'::text, 'triaged'::text, 'added_to_eval'::text, 'closed'::text])))
);

ALTER TABLE ONLY public.message_feedback FORCE ROW LEVEL SECURITY;


ALTER TABLE public.message_feedback OWNER TO postgres;

--
-- Name: messages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    role text NOT NULL,
    content text NOT NULL,
    answer_type text,
    confidence numeric(4,3),
    model text,
    prompt_tokens integer,
    completion_tokens integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT messages_answer_type_check CHECK ((answer_type = ANY (ARRAY['answered'::text, 'abstained'::text, 'refused'::text, 'error'::text]))),
    CONSTRAINT messages_role_check CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text])))
);

ALTER TABLE ONLY public.messages FORCE ROW LEVEL SECURITY;


ALTER TABLE public.messages OWNER TO postgres;

--
-- Name: permissions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.permissions (
    code text NOT NULL,
    description text NOT NULL
);


ALTER TABLE public.permissions OWNER TO postgres;

--
-- Name: pii_findings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pii_findings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    version_id uuid NOT NULL,
    chunk_id uuid,
    pii_type text NOT NULL,
    start_offset integer,
    end_offset integer,
    value_hash text,
    action text NOT NULL,
    CONSTRAINT pii_findings_action_check CHECK ((action = ANY (ARRAY['redacted'::text, 'masked'::text, 'flagged'::text, 'allowed'::text])))
);

ALTER TABLE ONLY public.pii_findings FORCE ROW LEVEL SECURITY;


ALTER TABLE public.pii_findings OWNER TO postgres;

--
-- Name: projects; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.projects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    key text NOT NULL,
    name text NOT NULL,
    description text,
    status text DEFAULT 'active'::text NOT NULL,
    default_classification smallint DEFAULT 1 NOT NULL,
    require_approval boolean DEFAULT false NOT NULL,
    owner_user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT projects_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text, 'deleted'::text])))
);

ALTER TABLE ONLY public.projects FORCE ROW LEVEL SECURITY;


ALTER TABLE public.projects OWNER TO postgres;

--
-- Name: query_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.query_logs (
    id integer NOT NULL,
    user_id uuid,
    team_id integer,
    session_id character varying(100),
    query text NOT NULL,
    response text NOT NULL,
    retrieved_document_ids text DEFAULT '[]'::text,
    citations_json text DEFAULT '[]'::text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.query_logs OWNER TO postgres;

--
-- Name: query_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.query_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.query_logs_id_seq OWNER TO postgres;

--
-- Name: query_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.query_logs_id_seq OWNED BY public.query_logs.id;


--
-- Name: retrieval_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.retrieval_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    message_id uuid,
    query_hash text NOT NULL,
    principal_count integer NOT NULL,
    principal_version bigint NOT NULL,
    filter_digest text NOT NULL,
    candidates_returned integer NOT NULL,
    dropped_by_postcheck integer DEFAULT 0 NOT NULL,
    selected_chunk_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    abstained boolean DEFAULT false NOT NULL,
    latency_ms integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.retrieval_events FORCE ROW LEVEL SECURITY;


ALTER TABLE public.retrieval_events OWNER TO postgres;

--
-- Name: role_assignments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.role_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    principal_type text NOT NULL,
    user_id uuid,
    group_id uuid,
    role_id uuid NOT NULL,
    project_id uuid,
    granted_by uuid,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    role_key character varying(50),
    scope_type character varying(50) DEFAULT 'tenant'::character varying,
    scope_id character varying(64),
    CONSTRAINT role_assignments_check CHECK ((((principal_type = 'user'::text) AND (user_id IS NOT NULL) AND (group_id IS NULL)) OR ((principal_type = 'group'::text) AND (group_id IS NOT NULL) AND (user_id IS NULL)))),
    CONSTRAINT role_assignments_principal_type_check CHECK ((principal_type = ANY (ARRAY['user'::text, 'group'::text])))
);

ALTER TABLE ONLY public.role_assignments FORCE ROW LEVEL SECURITY;


ALTER TABLE public.role_assignments OWNER TO postgres;

--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.role_permissions (
    role_id uuid NOT NULL,
    permission text NOT NULL
);


ALTER TABLE public.role_permissions OWNER TO postgres;

--
-- Name: roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid,
    name text NOT NULL,
    scope text NOT NULL,
    is_system boolean DEFAULT false NOT NULL,
    CONSTRAINT roles_scope_check CHECK ((scope = ANY (ARRAY['tenant'::text, 'project'::text])))
);

ALTER TABLE ONLY public.roles FORCE ROW LEVEL SECURITY;


ALTER TABLE public.roles OWNER TO postgres;

--
-- Name: source_connections; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.source_connections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    type text NOT NULL,
    name text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    credentials_ref text,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    default_project_id uuid,
    content_cursor text,
    acl_cursor text,
    acl_lag_sla_seconds integer DEFAULT 300 NOT NULL,
    last_synced_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT source_connections_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'error'::text, 'revoked'::text]))),
    CONSTRAINT source_connections_type_check CHECK ((type = ANY (ARRAY['manual'::text, 'gdrive'::text, 'sharepoint'::text, 'confluence'::text, 'slack'::text, 'teams'::text, 's3'::text, 'gov'::text])))
);

ALTER TABLE ONLY public.source_connections FORCE ROW LEVEL SECURITY;


ALTER TABLE public.source_connections OWNER TO postgres;

--
-- Name: sources; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sources (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    source_type character varying(50) DEFAULT 'google_drive'::character varying,
    uri text NOT NULL,
    drive_file_id character varying(128),
    folder_id character varying(128),
    status character varying(32) DEFAULT 'active'::character varying,
    metadata_json text,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.sources OWNER TO postgres;

--
-- Name: sources_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sources_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sources_id_seq OWNER TO postgres;

--
-- Name: sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sources_id_seq OWNED BY public.sources.id;


--
-- Name: sync_runs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sync_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    source_connection_id uuid NOT NULL,
    kind text NOT NULL,
    status text DEFAULT 'running'::text NOT NULL,
    stats jsonb DEFAULT '{}'::jsonb NOT NULL,
    error text,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    CONSTRAINT sync_runs_kind_check CHECK ((kind = ANY (ARRAY['full'::text, 'incremental'::text, 'acl_only'::text]))),
    CONSTRAINT sync_runs_status_check CHECK ((status = ANY (ARRAY['running'::text, 'succeeded'::text, 'failed'::text, 'partial'::text])))
);

ALTER TABLE ONLY public.sync_runs FORCE ROW LEVEL SECURITY;


ALTER TABLE public.sync_runs OWNER TO postgres;

--
-- Name: system_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.system_settings (
    key character varying(100) NOT NULL,
    value text NOT NULL,
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.system_settings OWNER TO postgres;

--
-- Name: team_chat_messages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.team_chat_messages (
    id integer NOT NULL,
    team_id integer,
    user_id uuid,
    user_email character varying(255),
    message text NOT NULL,
    response text NOT NULL,
    citations_json text DEFAULT '[]'::text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.team_chat_messages OWNER TO postgres;

--
-- Name: team_chat_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.team_chat_messages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.team_chat_messages_id_seq OWNER TO postgres;

--
-- Name: team_chat_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.team_chat_messages_id_seq OWNED BY public.team_chat_messages.id;


--
-- Name: team_members; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.team_members (
    id integer NOT NULL,
    team_id integer,
    user_id uuid,
    role_in_team character varying(50) DEFAULT 'member'::character varying,
    joined_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.team_members OWNER TO postgres;

--
-- Name: team_members_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.team_members_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.team_members_id_seq OWNER TO postgres;

--
-- Name: team_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.team_members_id_seq OWNED BY public.team_members.id;


--
-- Name: teams; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.teams (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    project_name character varying(150) NOT NULL,
    description text,
    created_by_id uuid,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.teams OWNER TO postgres;

--
-- Name: teams_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.teams_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.teams_id_seq OWNER TO postgres;

--
-- Name: teams_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.teams_id_seq OWNED BY public.teams.id;


--
-- Name: tenants; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tenants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug text NOT NULL,
    name text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    data_region text DEFAULT 'default'::text NOT NULL,
    kms_key_ref text,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tenants_status_check CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'deleting'::text])))
);

ALTER TABLE ONLY public.tenants FORCE ROW LEVEL SECURITY;


ALTER TABLE public.tenants OWNER TO postgres;

--
-- Name: user_group_closure; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_group_closure (
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    group_id uuid NOT NULL,
    id integer NOT NULL,
    depth integer DEFAULT 0
);

ALTER TABLE ONLY public.user_group_closure FORCE ROW LEVEL SECURITY;


ALTER TABLE public.user_group_closure OWNER TO postgres;

--
-- Name: user_group_closure_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_group_closure_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_group_closure_id_seq OWNER TO postgres;

--
-- Name: user_group_closure_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_group_closure_id_seq OWNED BY public.user_group_closure.id;


--
-- Name: user_groups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_groups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.user_groups OWNER TO postgres;

--
-- Name: user_idp_links; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_idp_links (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    idp_id uuid NOT NULL,
    subject text NOT NULL
);

ALTER TABLE ONLY public.user_idp_links FORCE ROW LEVEL SECURITY;


ALTER TABLE public.user_idp_links OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid,
    email public.citext NOT NULL,
    display_name text,
    status text DEFAULT 'active'::text NOT NULL,
    clearance_level smallint DEFAULT 1 NOT NULL,
    attributes jsonb DEFAULT '{}'::jsonb NOT NULL,
    principal_version bigint DEFAULT 1 NOT NULL,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    password_hash text,
    role text DEFAULT 'employee'::text,
    role_key text DEFAULT 'employee'::text,
    rank_level integer DEFAULT 5,
    is_active boolean DEFAULT true,
    created_by_id uuid,
    CONSTRAINT users_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text, 'deprovisioned'::text])))
);

ALTER TABLE ONLY public.users FORCE ROW LEVEL SECURITY;


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: audit_logs_default; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs ATTACH PARTITION public.audit_logs_default DEFAULT;


--
-- Name: acl_outbox id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.acl_outbox ALTER COLUMN id SET DEFAULT nextval('public.acl_outbox_id_seq'::regclass);


--
-- Name: company_roles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_roles ALTER COLUMN id SET DEFAULT nextval('public.company_roles_id_seq'::regclass);


--
-- Name: enterprise_admins id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enterprise_admins ALTER COLUMN id SET DEFAULT nextval('public.enterprise_admins_id_seq'::regclass);


--
-- Name: enterprise_drive_links id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enterprise_drive_links ALTER COLUMN id SET DEFAULT nextval('public.enterprise_drive_links_id_seq'::regclass);


--
-- Name: feedback id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.feedback ALTER COLUMN id SET DEFAULT nextval('public.feedback_id_seq'::regclass);


--
-- Name: query_logs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.query_logs ALTER COLUMN id SET DEFAULT nextval('public.query_logs_id_seq'::regclass);


--
-- Name: sources id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sources ALTER COLUMN id SET DEFAULT nextval('public.sources_id_seq'::regclass);


--
-- Name: team_chat_messages id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team_chat_messages ALTER COLUMN id SET DEFAULT nextval('public.team_chat_messages_id_seq'::regclass);


--
-- Name: team_members id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team_members ALTER COLUMN id SET DEFAULT nextval('public.team_members_id_seq'::regclass);


--
-- Name: teams id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teams ALTER COLUMN id SET DEFAULT nextval('public.teams_id_seq'::regclass);


--
-- Name: user_group_closure id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_group_closure ALTER COLUMN id SET DEFAULT nextval('public.user_group_closure_id_seq'::regclass);


--
-- Data for Name: abac_policies; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.abac_policies (id, tenant_id, name, effect, priority, enforcement, condition, enabled, version, created_by, created_at) FROM stdin;
\.


--
-- Data for Name: acl_outbox; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.acl_outbox (id, tenant_id, document_id, acl_version, status, attempts, created_at, processed_at) FROM stdin;
1	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	fc4d3e65-8349-48ab-a17f-c3058d7a7c6f	2	done	0	2026-10-06 21:55:33.603385+05:30	2026-10-07 13:04:24.722348+05:30
2	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	4d2b51ad-a4d8-4245-9c5e-81711be59246	2	done	0	2026-10-06 21:55:33.741573+05:30	2026-10-07 13:04:24.733723+05:30
3	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	4d2b51ad-a4d8-4245-9c5e-81711be59246	3	done	0	2026-10-06 21:55:33.741573+05:30	2026-10-07 13:04:24.746059+05:30
4	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f2ba76e4-3d6c-46ac-9536-449356a96909	2	done	0	2026-10-06 21:55:33.807034+05:30	2026-10-07 13:04:24.779786+05:30
5	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	d532e7ee-2a31-4823-9d3f-1b01ec25497e	2	done	0	2026-10-06 21:55:33.887445+05:30	2026-10-07 13:04:24.811889+05:30
6	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	576986c6-028c-4492-89a4-7416be6332be	2	done	0	2026-10-06 21:55:33.989776+05:30	2026-10-07 13:04:24.822012+05:30
7	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	366e4eac-d6b2-445e-baa2-2fc6621d60b0	2	done	0	2026-10-06 21:55:34.102988+05:30	2026-10-07 13:04:24.85489+05:30
8	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	d7304521-5288-42c0-ac8e-411017b9c101	2	done	0	2026-10-06 21:55:34.180777+05:30	2026-10-07 13:04:24.886865+05:30
9	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	5e665cd8-f070-45bb-a009-7dea79f3898b	2	done	0	2026-10-06 21:55:34.250186+05:30	2026-10-07 13:04:24.91793+05:30
10	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e1f37cdd-b3ef-4a97-bbfb-54ab4c119358	2	done	0	2026-10-06 21:55:34.324162+05:30	2026-10-07 13:04:24.953098+05:30
11	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	dd37ed5c-b8b3-47de-bf74-c07ff069b3a8	2	done	0	2026-10-06 21:55:34.399458+05:30	2026-10-07 13:04:24.98085+05:30
12	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0cdabf35-6d82-49a3-bcf8-532fe826f025	2	done	0	2026-10-06 21:55:34.454266+05:30	2026-10-07 13:04:25.013006+05:30
13	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	2f598d2a-b04e-487b-b26c-bac0ab79f0d9	2	done	0	2026-10-06 21:55:34.518147+05:30	2026-10-07 13:04:25.043775+05:30
14	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	eda34d3a-eff6-48ca-9280-f663b5ca07b2	2	done	0	2026-10-06 21:55:34.598783+05:30	2026-10-07 13:04:25.074692+05:30
15	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	9c0ec190-25ef-4314-829b-b960e2e8575d	2	done	0	2026-10-06 21:55:34.680339+05:30	2026-10-07 13:04:25.10719+05:30
16	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	9c0ec190-25ef-4314-829b-b960e2e8575d	3	done	0	2026-10-06 21:55:34.680339+05:30	2026-10-07 13:04:25.132721+05:30
17	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	a0faa074-94ad-44ef-9471-0e6e50416f46	2	done	0	2026-10-06 22:00:50.742298+05:30	2026-10-07 13:04:25.166813+05:30
18	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	a0faa074-94ad-44ef-9471-0e6e50416f46	3	done	0	2026-10-06 22:00:50.742298+05:30	2026-10-07 13:04:25.197959+05:30
130	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	45b10e4d-8bb7-49f5-8f77-751cc4c8f292	3	done	0	2026-10-07 11:29:52.803004+05:30	2026-10-07 13:04:25.229892+05:30
65	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	fc4d3e65-8349-48ab-a17f-c3058d7a7c6f	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.260075+05:30
66	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	4d2b51ad-a4d8-4245-9c5e-81711be59246	4	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.272934+05:30
67	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	4d2b51ad-a4d8-4245-9c5e-81711be59246	5	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.281202+05:30
68	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f2ba76e4-3d6c-46ac-9536-449356a96909	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.303276+05:30
69	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	d532e7ee-2a31-4823-9d3f-1b01ec25497e	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.332991+05:30
71	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	366e4eac-d6b2-445e-baa2-2fc6621d60b0	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.350532+05:30
72	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	d7304521-5288-42c0-ac8e-411017b9c101	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.363004+05:30
73	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	5e665cd8-f070-45bb-a009-7dea79f3898b	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.396137+05:30
74	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e1f37cdd-b3ef-4a97-bbfb-54ab4c119358	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.426335+05:30
75	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	dd37ed5c-b8b3-47de-bf74-c07ff069b3a8	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.45727+05:30
76	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0cdabf35-6d82-49a3-bcf8-532fe826f025	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.465537+05:30
77	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	2f598d2a-b04e-487b-b26c-bac0ab79f0d9	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.489483+05:30
78	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	eda34d3a-eff6-48ca-9280-f663b5ca07b2	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.498546+05:30
79	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	9c0ec190-25ef-4314-829b-b960e2e8575d	4	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.505949+05:30
80	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	9c0ec190-25ef-4314-829b-b960e2e8575d	5	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.514031+05:30
82	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	a0faa074-94ad-44ef-9471-0e6e50416f46	5	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.553767+05:30
129	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	45b10e4d-8bb7-49f5-8f77-751cc4c8f292	2	done	0	2026-10-07 11:29:18.253647+05:30	2026-10-07 13:04:25.584278+05:30
154	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	821709cd-804b-4fa8-8248-aea199f33c25	2	done	0	2026-10-07 11:34:28.883851+05:30	2026-10-07 13:04:25.590372+05:30
155	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	821709cd-804b-4fa8-8248-aea199f33c25	3	done	0	2026-10-07 11:34:28.883851+05:30	2026-10-07 13:04:25.599702+05:30
156	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0cae3952-0367-42d3-ae95-6292b040bd78	2	done	0	2026-10-07 11:34:33.821513+05:30	2026-10-07 13:04:25.632703+05:30
157	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0cae3952-0367-42d3-ae95-6292b040bd78	3	done	0	2026-10-07 11:34:33.821513+05:30	2026-10-07 13:04:25.66412+05:30
158	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	99c59e4e-859e-4fbb-b73d-ef74255c7959	2	done	0	2026-10-07 11:34:34.272371+05:30	2026-10-07 13:04:25.692256+05:30
159	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	99c59e4e-859e-4fbb-b73d-ef74255c7959	3	done	0	2026-10-07 11:34:34.272371+05:30	2026-10-07 13:04:25.725527+05:30
160	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	6a0bdfef-e2e0-4ae6-9ff6-f961b823aae7	2	done	0	2026-10-07 11:34:34.865246+05:30	2026-10-07 13:04:25.756471+05:30
161	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	6a0bdfef-e2e0-4ae6-9ff6-f961b823aae7	3	done	0	2026-10-07 11:34:34.865246+05:30	2026-10-07 13:04:25.765659+05:30
163	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f9e16941-656d-448f-b9ac-afc7266e08fa	3	done	0	2026-10-07 11:34:35.827699+05:30	2026-10-07 13:04:25.816435+05:30
164	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0c9306b3-b762-4445-a63d-860d2c264ae7	2	done	0	2026-10-07 11:34:36.277459+05:30	2026-10-07 13:04:25.833564+05:30
165	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0c9306b3-b762-4445-a63d-860d2c264ae7	3	done	0	2026-10-07 11:34:36.277459+05:30	2026-10-07 13:04:25.84221+05:30
166	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bf65933a-d596-4ee3-8eec-e02439471f21	2	done	0	2026-10-07 11:34:36.990999+05:30	2026-10-07 13:04:25.849694+05:30
167	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bf65933a-d596-4ee3-8eec-e02439471f21	3	done	0	2026-10-07 11:34:36.990999+05:30	2026-10-07 13:04:25.857984+05:30
168	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	7baec03d-595f-46b9-b318-812bfb26a367	2	done	0	2026-10-07 11:34:37.663184+05:30	2026-10-07 13:04:25.865157+05:30
169	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	7baec03d-595f-46b9-b318-812bfb26a367	3	done	0	2026-10-07 11:34:37.663184+05:30	2026-10-07 13:04:25.872703+05:30
170	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	6ea34021-5d19-48e2-ba00-06c5940748ac	2	done	0	2026-10-07 11:34:37.956374+05:30	2026-10-07 13:04:25.881355+05:30
171	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	8a38d06e-a555-4a26-afcd-5497187371bd	2	done	0	2026-10-07 11:34:38.777414+05:30	2026-10-07 13:04:25.909837+05:30
172	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bc95f7c6-8a8c-42eb-99d1-4384380c80d4	2	done	0	2026-10-07 11:34:39.407995+05:30	2026-10-07 13:04:25.941814+05:30
174	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	8403a264-5148-47cd-9103-696d0038f21b	2	done	0	2026-10-07 11:34:41.760075+05:30	2026-10-07 13:04:25.989855+05:30
175	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	53e5e91e-06e4-4dc3-8880-d86bbb4e7d02	2	done	0	2026-10-07 11:34:42.574159+05:30	2026-10-07 13:04:25.998901+05:30
176	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	8a3666c1-3769-48a8-b241-31519dca1e8b	2	done	0	2026-10-07 11:34:43.553363+05:30	2026-10-07 13:04:26.005617+05:30
180	\N	doc-2e8e5dd3f7f3	2	done	0	2026-10-07 13:01:44.611246+05:30	2026-10-07 13:04:26.015746+05:30
181	\N	doc-2e8e5dd3f7f3	3	done	0	2026-10-07 13:04:24.69653+05:30	2026-10-07 13:04:26.022461+05:30
70	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	576986c6-028c-4492-89a4-7416be6332be	3	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.340461+05:30
81	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	a0faa074-94ad-44ef-9471-0e6e50416f46	4	done	0	2026-10-07 11:23:45.822452+05:30	2026-10-07 13:04:25.521775+05:30
162	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f9e16941-656d-448f-b9ac-afc7266e08fa	2	done	0	2026-10-07 11:34:35.827699+05:30	2026-10-07 13:04:25.787218+05:30
173	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	ce7bc5dd-4346-490f-a26f-24b6451e2528	2	done	0	2026-10-07 11:34:40.782881+05:30	2026-10-07 13:04:25.972341+05:30
182	\N	doc-2fef237a53e6	2	done	0	2026-10-07 13:04:42.249238+05:30	2026-10-07 13:04:42.266651+05:30
183	\N	doc-90522638f048	2	done	0	2026-10-07 13:04:59.534627+05:30	2026-10-07 13:04:59.544843+05:30
184	\N	doc-2e8e5dd3f7f3	4	done	0	2026-10-07 13:28:20.837453+05:30	2026-10-07 13:28:20.888593+05:30
185	\N	doc-2fef237a53e6	3	done	0	2026-10-07 13:28:20.902926+05:30	2026-10-07 13:28:20.931599+05:30
186	\N	doc-90522638f048	3	done	0	2026-10-07 13:28:20.965095+05:30	2026-10-07 13:28:20.997+05:30
187	\N	doc-2e8e5dd3f7f3	5	done	0	2026-10-07 13:33:57.03417+05:30	2026-10-07 13:33:57.080373+05:30
188	\N	doc-2fef237a53e6	4	done	0	2026-10-07 13:33:57.117138+05:30	2026-10-07 13:33:57.210752+05:30
189	\N	doc-90522638f048	4	done	0	2026-10-07 13:33:57.239354+05:30	2026-10-07 13:33:57.266432+05:30
190	\N	doc-2e8e5dd3f7f3	6	done	0	2026-10-07 13:34:40.505893+05:30	2026-10-07 13:34:40.544806+05:30
191	\N	doc-2fef237a53e6	5	done	0	2026-10-07 13:34:40.587423+05:30	2026-10-07 13:34:40.608211+05:30
192	\N	doc-90522638f048	5	done	0	2026-10-07 13:34:40.631985+05:30	2026-10-07 13:34:40.653552+05:30
193	\N	doc-2e8e5dd3f7f3	7	done	0	2026-10-07 13:34:45.836503+05:30	2026-10-07 13:34:45.870002+05:30
194	\N	doc-2fef237a53e6	6	done	0	2026-10-07 13:34:45.902011+05:30	2026-10-07 13:34:45.933075+05:30
195	\N	doc-90522638f048	6	done	0	2026-10-07 13:34:45.97131+05:30	2026-10-07 13:34:45.994983+05:30
196	\N	doc-2e8e5dd3f7f3	8	done	0	2026-10-07 13:35:49.134911+05:30	2026-10-07 13:35:49.167571+05:30
197	\N	doc-2fef237a53e6	7	done	0	2026-10-07 13:35:49.200377+05:30	2026-10-07 13:35:49.215317+05:30
198	\N	doc-90522638f048	7	done	0	2026-10-07 13:35:49.247629+05:30	2026-10-07 13:35:49.261334+05:30
255	\N	doc-a99b3249e8be	5	done	0	2026-10-07 15:24:29.920526+05:30	2026-10-07 15:24:29.98126+05:30
199	\N	doc-2e8e5dd3f7f3	9	done	0	2026-10-07 13:36:34.533215+05:30	2026-10-07 13:36:34.565201+05:30
256	\N	doc-2e8e5dd3f7f3	13	done	0	2026-10-07 15:24:30.004003+05:30	2026-10-07 15:24:30.038956+05:30
200	\N	doc-2fef237a53e6	8	done	0	2026-10-07 13:36:34.603251+05:30	2026-10-07 13:36:34.649185+05:30
201	\N	doc-f99607221cc6	2	done	0	2026-10-07 13:37:18.627002+05:30	2026-10-07 13:37:18.669953+05:30
202	\N	doc-a99b3249e8be	2	done	0	2026-10-07 13:38:43.77966+05:30	2026-10-07 13:38:43.795555+05:30
257	\N	doc-4741b651e377	5	done	0	2026-10-07 15:24:30.087201+05:30	2026-10-07 15:24:30.115456+05:30
203	\N	doc-2e8e5dd3f7f3	10	done	0	2026-10-07 13:38:43.846459+05:30	2026-10-07 13:38:43.866443+05:30
204	\N	doc-4741b651e377	2	done	0	2026-10-07 13:38:47.180942+05:30	2026-10-07 13:38:47.208413+05:30
205	\N	doc-754fa9684aed	2	done	0	2026-10-07 13:38:51.382433+05:30	2026-10-07 13:38:51.399638+05:30
206	\N	doc-e57f3124b6a2	2	done	0	2026-10-07 13:38:55.507777+05:30	2026-10-07 13:38:55.525722+05:30
207	\N	doc-130b39d15af6	2	done	0	2026-10-07 13:38:58.921365+05:30	2026-10-07 13:38:58.936944+05:30
208	\N	doc-68237f22039b	2	done	0	2026-10-07 13:39:03.71837+05:30	2026-10-07 13:39:03.749615+05:30
209	\N	doc-ef22084066f3	2	done	0	2026-10-07 13:39:07.752085+05:30	2026-10-07 13:39:07.784862+05:30
210	\N	doc-3084996f8617	2	done	0	2026-10-07 13:39:11.730399+05:30	2026-10-07 13:39:11.762595+05:30
211	\N	doc-2ada98486ec4	2	done	0	2026-10-07 13:39:17.243156+05:30	2026-10-07 13:39:17.287653+05:30
212	\N	doc-3b3dd582127c	2	done	0	2026-10-07 13:39:22.162911+05:30	2026-10-07 13:39:22.178255+05:30
213	\N	doc-f99607221cc6	3	done	0	2026-10-07 13:39:22.22489+05:30	2026-10-07 13:39:22.265367+05:30
214	\N	doc-21379031a248	2	done	0	2026-10-07 13:39:25.980414+05:30	2026-10-07 13:39:26.000515+05:30
215	\N	doc-fd7fd7ba8702	2	done	0	2026-10-07 13:39:30.178445+05:30	2026-10-07 13:39:30.224058+05:30
216	\N	doc-f4de4672f657	2	done	0	2026-10-07 13:39:33.802279+05:30	2026-10-07 13:39:33.828405+05:30
217	\N	doc-27eadc26a7a2	2	done	0	2026-10-07 13:39:37.566523+05:30	2026-10-07 13:39:37.602105+05:30
218	\N	doc-f34d3b0e0c4d	2	done	0	2026-10-07 13:39:40.67705+05:30	2026-10-07 13:39:40.714754+05:30
219	\N	doc-f34d3b0e0c4d	3	done	0	2026-10-07 13:40:44.399255+05:30	2026-10-07 13:40:44.434106+05:30
220	\N	doc-27eadc26a7a2	3	done	0	2026-10-07 13:41:04.743929+05:30	2026-10-07 13:41:04.782659+05:30
221	\N	doc-a99b3249e8be	3	done	0	2026-10-07 15:10:56.501061+05:30	2026-10-07 15:10:56.570403+05:30
222	\N	doc-2e8e5dd3f7f3	11	done	0	2026-10-07 15:10:56.606803+05:30	2026-10-07 15:10:56.633001+05:30
223	\N	doc-4741b651e377	3	done	0	2026-10-07 15:10:56.672617+05:30	2026-10-07 15:10:56.715703+05:30
224	\N	doc-754fa9684aed	3	done	0	2026-10-07 15:10:56.761931+05:30	2026-10-07 15:10:56.79017+05:30
225	\N	doc-e57f3124b6a2	3	done	0	2026-10-07 15:10:56.823495+05:30	2026-10-07 15:10:56.85438+05:30
226	\N	doc-130b39d15af6	3	done	0	2026-10-07 15:10:56.892632+05:30	2026-10-07 15:10:56.931879+05:30
227	\N	doc-68237f22039b	3	done	0	2026-10-07 15:10:56.962818+05:30	2026-10-07 15:10:56.997368+05:30
228	\N	doc-ef22084066f3	3	done	0	2026-10-07 15:10:57.03754+05:30	2026-10-07 15:10:57.09462+05:30
229	\N	doc-3084996f8617	3	done	0	2026-10-07 15:10:57.136265+05:30	2026-10-07 15:10:57.154394+05:30
230	\N	doc-2ada98486ec4	3	done	0	2026-10-07 15:10:57.197298+05:30	2026-10-07 15:10:57.241857+05:30
231	\N	doc-3b3dd582127c	3	done	0	2026-10-07 15:10:57.290728+05:30	2026-10-07 15:10:57.333207+05:30
232	\N	doc-f99607221cc6	4	done	0	2026-10-07 15:10:57.374519+05:30	2026-10-07 15:10:57.420325+05:30
233	\N	doc-21379031a248	3	done	0	2026-10-07 15:10:57.436143+05:30	2026-10-07 15:10:57.460239+05:30
234	\N	doc-fd7fd7ba8702	3	done	0	2026-10-07 15:10:57.476814+05:30	2026-10-07 15:10:57.509116+05:30
235	\N	doc-f4de4672f657	3	done	0	2026-10-07 15:10:57.540761+05:30	2026-10-07 15:10:57.569428+05:30
236	\N	doc-27eadc26a7a2	4	done	0	2026-10-07 15:10:57.587529+05:30	2026-10-07 15:10:57.615842+05:30
237	\N	doc-f34d3b0e0c4d	4	done	0	2026-10-07 15:10:57.65152+05:30	2026-10-07 15:10:57.67888+05:30
238	\N	doc-a99b3249e8be	4	done	0	2026-10-07 15:14:46.036274+05:30	2026-10-07 15:14:46.084505+05:30
239	\N	doc-2e8e5dd3f7f3	12	done	0	2026-10-07 15:14:46.118626+05:30	2026-10-07 15:14:46.141071+05:30
240	\N	doc-4741b651e377	4	done	0	2026-10-07 15:14:46.175522+05:30	2026-10-07 15:14:46.203077+05:30
241	\N	doc-754fa9684aed	4	done	0	2026-10-07 15:14:46.239459+05:30	2026-10-07 15:14:46.268597+05:30
242	\N	doc-e57f3124b6a2	4	done	0	2026-10-07 15:14:46.313939+05:30	2026-10-07 15:14:46.344567+05:30
243	\N	doc-130b39d15af6	4	done	0	2026-10-07 15:14:46.373666+05:30	2026-10-07 15:14:46.404009+05:30
244	\N	doc-68237f22039b	4	done	0	2026-10-07 15:14:46.465531+05:30	2026-10-07 15:14:46.511686+05:30
245	\N	doc-ef22084066f3	4	done	0	2026-10-07 15:14:46.536567+05:30	2026-10-07 15:14:46.556681+05:30
246	\N	doc-3084996f8617	4	done	0	2026-10-07 15:14:46.590754+05:30	2026-10-07 15:14:46.621205+05:30
247	\N	doc-2ada98486ec4	4	done	0	2026-10-07 15:14:46.661961+05:30	2026-10-07 15:14:46.700726+05:30
248	\N	doc-3b3dd582127c	4	done	0	2026-10-07 15:14:46.745017+05:30	2026-10-07 15:14:46.786979+05:30
249	\N	doc-f99607221cc6	5	done	0	2026-10-07 15:14:46.805987+05:30	2026-10-07 15:14:46.820787+05:30
250	\N	doc-21379031a248	4	done	0	2026-10-07 15:14:46.84265+05:30	2026-10-07 15:14:46.854619+05:30
251	\N	doc-fd7fd7ba8702	4	done	0	2026-10-07 15:14:46.872356+05:30	2026-10-07 15:14:46.909058+05:30
252	\N	doc-f4de4672f657	4	done	0	2026-10-07 15:14:46.941149+05:30	2026-10-07 15:14:46.969661+05:30
253	\N	doc-27eadc26a7a2	5	done	0	2026-10-07 15:14:47.003182+05:30	2026-10-07 15:14:47.028737+05:30
254	\N	doc-f34d3b0e0c4d	5	done	0	2026-10-07 15:14:47.076582+05:30	2026-10-07 15:14:47.094118+05:30
258	\N	doc-754fa9684aed	5	done	0	2026-10-07 15:24:30.153495+05:30	2026-10-07 15:24:30.180568+05:30
259	\N	doc-e57f3124b6a2	5	done	0	2026-10-07 15:24:30.215441+05:30	2026-10-07 15:24:30.240145+05:30
260	\N	doc-130b39d15af6	5	done	0	2026-10-07 15:24:30.292483+05:30	2026-10-07 15:24:30.319014+05:30
261	\N	doc-68237f22039b	5	done	0	2026-10-07 15:24:30.352077+05:30	2026-10-07 15:24:30.381422+05:30
262	\N	doc-ef22084066f3	5	done	0	2026-10-07 15:24:30.419254+05:30	2026-10-07 15:24:30.46193+05:30
263	\N	doc-3084996f8617	5	done	0	2026-10-07 15:24:30.492668+05:30	2026-10-07 15:24:30.521709+05:30
264	\N	doc-2ada98486ec4	5	done	0	2026-10-07 15:24:30.555738+05:30	2026-10-07 15:24:30.583839+05:30
265	\N	doc-3b3dd582127c	5	done	0	2026-10-07 15:24:30.61663+05:30	2026-10-07 15:24:30.647863+05:30
266	\N	doc-f99607221cc6	6	done	0	2026-10-07 15:24:30.67811+05:30	2026-10-07 15:24:30.69059+05:30
267	\N	doc-21379031a248	5	done	0	2026-10-07 15:24:30.725485+05:30	2026-10-07 15:24:30.75724+05:30
268	\N	doc-fd7fd7ba8702	5	done	0	2026-10-07 15:24:30.787304+05:30	2026-10-07 15:24:30.815433+05:30
269	\N	doc-f4de4672f657	5	done	0	2026-10-07 15:24:30.855119+05:30	2026-10-07 15:24:30.886484+05:30
270	\N	doc-27eadc26a7a2	6	done	0	2026-10-07 15:24:30.928449+05:30	2026-10-07 15:24:30.957231+05:30
271	\N	doc-f34d3b0e0c4d	6	done	0	2026-10-07 15:24:30.990124+05:30	2026-10-07 15:24:31.016972+05:30
353	\N	doc-0718297b71e4	2	done	0	2026-10-08 15:06:51.951685+05:30	2026-10-08 15:06:52.008683+05:30
272	\N	doc-a99b3249e8be	6	done	0	2026-10-07 15:24:42.745623+05:30	2026-10-07 15:24:42.781507+05:30
273	\N	doc-2e8e5dd3f7f3	14	done	0	2026-10-07 15:24:42.81959+05:30	2026-10-07 15:24:42.844517+05:30
274	\N	doc-4741b651e377	6	done	0	2026-10-07 15:24:42.876096+05:30	2026-10-07 15:24:42.905116+05:30
275	\N	doc-754fa9684aed	6	done	0	2026-10-07 15:24:42.9421+05:30	2026-10-07 15:24:42.985568+05:30
276	\N	doc-e57f3124b6a2	6	done	0	2026-10-07 15:24:43.034611+05:30	2026-10-07 15:24:43.060885+05:30
277	\N	doc-130b39d15af6	6	done	0	2026-10-07 15:24:43.095222+05:30	2026-10-07 15:24:43.121141+05:30
278	\N	doc-68237f22039b	6	done	0	2026-10-07 15:24:43.139171+05:30	2026-10-07 15:24:43.152176+05:30
279	\N	doc-ef22084066f3	6	done	0	2026-10-07 15:24:43.172515+05:30	2026-10-07 15:24:43.197938+05:30
280	\N	doc-3084996f8617	6	done	0	2026-10-07 15:24:43.215333+05:30	2026-10-07 15:24:43.245133+05:30
281	\N	doc-2ada98486ec4	6	done	0	2026-10-07 15:24:43.281186+05:30	2026-10-07 15:24:43.306161+05:30
282	\N	doc-3b3dd582127c	6	done	0	2026-10-07 15:24:43.340342+05:30	2026-10-07 15:24:43.369317+05:30
283	\N	doc-f99607221cc6	7	done	0	2026-10-07 15:24:43.389857+05:30	2026-10-07 15:24:43.414454+05:30
284	\N	doc-21379031a248	6	done	0	2026-10-07 15:24:43.449681+05:30	2026-10-07 15:24:43.482553+05:30
285	\N	doc-fd7fd7ba8702	6	done	0	2026-10-07 15:24:43.527293+05:30	2026-10-07 15:24:43.553782+05:30
286	\N	doc-f4de4672f657	6	done	0	2026-10-07 15:24:43.590463+05:30	2026-10-07 15:24:43.636217+05:30
287	\N	doc-27eadc26a7a2	7	done	0	2026-10-07 15:24:43.686383+05:30	2026-10-07 15:24:43.758902+05:30
288	\N	doc-f34d3b0e0c4d	7	done	0	2026-10-07 15:24:43.785448+05:30	2026-10-07 15:24:43.814668+05:30
289	\N	doc-f4de4672f657	7	done	0	2026-10-07 15:27:01.120623+05:30	2026-10-07 15:27:01.194987+05:30
290	\N	doc-a99b3249e8be	7	done	0	2026-10-07 15:30:03.893092+05:30	2026-10-07 15:30:03.931284+05:30
291	\N	doc-2e8e5dd3f7f3	15	done	0	2026-10-07 15:30:03.995091+05:30	2026-10-07 15:30:04.030906+05:30
292	\N	doc-4741b651e377	7	done	0	2026-10-07 15:30:04.075806+05:30	2026-10-07 15:30:04.119149+05:30
293	\N	doc-754fa9684aed	7	done	0	2026-10-07 15:30:04.178419+05:30	2026-10-07 15:30:04.215722+05:30
294	\N	doc-e57f3124b6a2	7	done	0	2026-10-07 15:30:04.287643+05:30	2026-10-07 15:30:04.322266+05:30
295	\N	doc-130b39d15af6	7	done	0	2026-10-07 15:30:04.377547+05:30	2026-10-07 15:30:04.418415+05:30
296	\N	doc-68237f22039b	7	done	0	2026-10-07 15:30:04.46294+05:30	2026-10-07 15:30:04.518061+05:30
297	\N	doc-ef22084066f3	7	done	0	2026-10-07 15:30:04.576879+05:30	2026-10-07 15:30:04.605547+05:30
298	\N	doc-3084996f8617	7	done	0	2026-10-07 15:30:04.682362+05:30	2026-10-07 15:30:04.706039+05:30
299	\N	doc-2ada98486ec4	7	done	0	2026-10-07 15:30:04.770676+05:30	2026-10-07 15:30:04.808829+05:30
300	\N	doc-3b3dd582127c	7	done	0	2026-10-07 15:30:04.861533+05:30	2026-10-07 15:30:04.895361+05:30
301	\N	doc-f99607221cc6	8	done	0	2026-10-07 15:30:04.968306+05:30	2026-10-07 15:30:04.9946+05:30
302	\N	doc-21379031a248	7	done	0	2026-10-07 15:30:05.068009+05:30	2026-10-07 15:30:05.099063+05:30
303	\N	doc-fd7fd7ba8702	7	done	0	2026-10-07 15:30:05.140742+05:30	2026-10-07 15:30:05.160601+05:30
304	\N	doc-f4de4672f657	8	done	0	2026-10-07 15:30:05.21914+05:30	2026-10-07 15:30:05.274032+05:30
305	\N	doc-27eadc26a7a2	8	done	0	2026-10-07 15:30:05.333085+05:30	2026-10-07 15:30:05.36383+05:30
306	\N	doc-f34d3b0e0c4d	8	done	0	2026-10-07 15:30:05.395796+05:30	2026-10-07 15:30:05.438457+05:30
307	\N	doc-a99b3249e8be	8	done	0	2026-10-07 15:30:17.799196+05:30	2026-10-07 15:30:17.835588+05:30
308	\N	doc-2e8e5dd3f7f3	16	done	0	2026-10-07 15:30:17.914964+05:30	2026-10-07 15:30:17.966223+05:30
309	\N	doc-4741b651e377	8	done	0	2026-10-07 15:30:18.025284+05:30	2026-10-07 15:30:18.057405+05:30
310	\N	doc-754fa9684aed	8	done	0	2026-10-07 15:30:18.112188+05:30	2026-10-07 15:30:18.135958+05:30
311	\N	doc-e57f3124b6a2	8	done	0	2026-10-07 15:30:18.181823+05:30	2026-10-07 15:30:18.209334+05:30
312	\N	doc-130b39d15af6	8	done	0	2026-10-07 15:30:18.266814+05:30	2026-10-07 15:30:18.30092+05:30
313	\N	doc-68237f22039b	8	done	0	2026-10-07 15:30:18.360928+05:30	2026-10-07 15:30:18.389747+05:30
314	\N	doc-ef22084066f3	8	done	0	2026-10-07 15:30:18.449072+05:30	2026-10-07 15:30:18.476359+05:30
315	\N	doc-3084996f8617	8	done	0	2026-10-07 15:30:18.508626+05:30	2026-10-07 15:30:18.527238+05:30
316	\N	doc-2ada98486ec4	8	done	0	2026-10-07 15:30:18.559492+05:30	2026-10-07 15:30:18.580642+05:30
317	\N	doc-3b3dd582127c	8	done	0	2026-10-07 15:30:18.618536+05:30	2026-10-07 15:30:18.634252+05:30
318	\N	doc-f99607221cc6	9	done	0	2026-10-07 15:30:18.682439+05:30	2026-10-07 15:30:18.725014+05:30
319	\N	doc-21379031a248	8	done	0	2026-10-07 15:30:18.773685+05:30	2026-10-07 15:30:18.816693+05:30
320	\N	doc-fd7fd7ba8702	8	done	0	2026-10-07 15:30:18.867218+05:30	2026-10-07 15:30:18.906449+05:30
321	\N	doc-f4de4672f657	9	done	0	2026-10-07 15:30:18.942754+05:30	2026-10-07 15:30:18.969545+05:30
322	\N	doc-27eadc26a7a2	9	done	0	2026-10-07 15:30:18.995488+05:30	2026-10-07 15:30:19.023602+05:30
323	\N	doc-f34d3b0e0c4d	9	done	0	2026-10-07 15:30:19.066639+05:30	2026-10-07 15:30:19.093096+05:30
324	\N	doc-130b39d15af6	9	done	0	2026-10-08 14:47:49.06887+05:30	2026-10-08 14:47:49.154729+05:30
325	\N	doc-68237f22039b	9	done	0	2026-10-08 14:47:49.199433+05:30	2026-10-08 14:47:49.230913+05:30
326	\N	doc-ef22084066f3	9	done	0	2026-10-08 14:47:49.284239+05:30	2026-10-08 14:47:49.313493+05:30
327	\N	doc-3084996f8617	9	done	0	2026-10-08 14:47:49.397969+05:30	2026-10-08 14:47:49.436555+05:30
328	\N	doc-2ada98486ec4	9	done	0	2026-10-08 14:47:49.482625+05:30	2026-10-08 14:47:49.514135+05:30
329	\N	doc-3b3dd582127c	9	done	0	2026-10-08 14:47:49.558497+05:30	2026-10-08 14:47:49.578831+05:30
330	\N	doc-f99607221cc6	10	done	0	2026-10-08 14:47:49.618074+05:30	2026-10-08 14:47:49.632767+05:30
331	\N	doc-21379031a248	9	done	0	2026-10-08 14:47:49.684774+05:30	2026-10-08 14:47:49.701588+05:30
332	\N	doc-fd7fd7ba8702	9	done	0	2026-10-08 14:47:49.739459+05:30	2026-10-08 14:47:49.756297+05:30
333	\N	doc-f4de4672f657	10	done	0	2026-10-08 14:47:49.788706+05:30	2026-10-08 14:47:49.827833+05:30
334	\N	doc-27eadc26a7a2	10	done	0	2026-10-08 14:47:49.865261+05:30	2026-10-08 14:47:49.885516+05:30
335	\N	doc-f34d3b0e0c4d	10	done	0	2026-10-08 14:47:49.933195+05:30	2026-10-08 14:47:49.948969+05:30
475	\N	doc-0718297b71e4	9	done	0	2026-10-09 04:26:52.030112+05:30	2026-10-09 04:26:52.107352+05:30
336	\N	doc-a99b3249e8be	9	done	0	2026-10-08 14:54:01.181201+05:30	2026-10-08 14:54:01.23458+05:30
354	\N	doc-de573a503f6d	2	done	0	2026-10-08 15:06:52.956969+05:30	2026-10-08 15:06:52.994085+05:30
337	\N	doc-2e8e5dd3f7f3	17	done	0	2026-10-08 14:54:01.277742+05:30	2026-10-08 14:54:01.289475+05:30
355	\N	doc-03b90406eca2	2	done	0	2026-10-08 15:06:56.499868+05:30	2026-10-08 15:06:56.541681+05:30
338	\N	doc-4741b651e377	9	done	0	2026-10-08 14:54:01.337529+05:30	2026-10-08 14:54:01.3742+05:30
339	\N	doc-754fa9684aed	9	done	0	2026-10-08 14:54:01.413414+05:30	2026-10-08 14:54:01.435088+05:30
356	\N	doc-0a51cdb40625	2	done	0	2026-10-08 15:07:00.471566+05:30	2026-10-08 15:07:00.492634+05:30
340	\N	doc-e57f3124b6a2	9	done	0	2026-10-08 14:54:01.474097+05:30	2026-10-08 14:54:01.494024+05:30
357	\N	doc-9a4395663625	2	done	0	2026-10-08 15:07:04.821439+05:30	2026-10-08 15:07:04.848104+05:30
341	\N	doc-130b39d15af6	10	done	0	2026-10-08 14:54:01.54094+05:30	2026-10-08 14:54:01.564629+05:30
342	\N	doc-68237f22039b	10	done	0	2026-10-08 14:54:01.593971+05:30	2026-10-08 14:54:01.61877+05:30
358	\N	doc-becad9a82359	2	done	0	2026-10-08 15:07:08.52134+05:30	2026-10-08 15:07:08.539306+05:30
343	\N	doc-ef22084066f3	10	done	0	2026-10-08 14:54:01.6584+05:30	2026-10-08 14:54:01.671591+05:30
344	\N	doc-3084996f8617	10	done	0	2026-10-08 14:54:01.70587+05:30	2026-10-08 14:54:01.724334+05:30
359	\N	doc-b02ac5215dad	2	done	0	2026-10-08 15:07:12.924897+05:30	2026-10-08 15:07:12.944392+05:30
345	\N	doc-2ada98486ec4	10	done	0	2026-10-08 14:54:01.750668+05:30	2026-10-08 14:54:01.771103+05:30
346	\N	doc-3b3dd582127c	10	done	0	2026-10-08 14:54:01.812338+05:30	2026-10-08 14:54:01.824013+05:30
360	\N	doc-37cea547ae24	2	done	0	2026-10-08 15:07:17.538138+05:30	2026-10-08 15:07:17.556571+05:30
347	\N	doc-f99607221cc6	11	done	0	2026-10-08 14:54:01.846516+05:30	2026-10-08 14:54:01.861056+05:30
348	\N	doc-21379031a248	10	done	0	2026-10-08 14:54:01.885189+05:30	2026-10-08 14:54:01.908339+05:30
361	\N	doc-5e4f6cd7d179	2	done	0	2026-10-08 15:07:21.489391+05:30	2026-10-08 15:07:21.524743+05:30
349	\N	doc-fd7fd7ba8702	10	done	0	2026-10-08 14:54:01.932723+05:30	2026-10-08 14:54:01.945684+05:30
350	\N	doc-f4de4672f657	11	done	0	2026-10-08 14:54:01.980986+05:30	2026-10-08 14:54:02.015865+05:30
362	\N	doc-a453aa814971	2	done	0	2026-10-08 15:07:27.38254+05:30	2026-10-08 15:07:27.415299+05:30
351	\N	doc-27eadc26a7a2	11	done	0	2026-10-08 14:54:02.055619+05:30	2026-10-08 14:54:02.076738+05:30
352	\N	doc-f34d3b0e0c4d	11	done	0	2026-10-08 14:54:02.101792+05:30	2026-10-08 14:54:02.122479+05:30
363	\N	doc-e9cdba142890	2	done	0	2026-10-08 15:07:31.744107+05:30	2026-10-08 15:07:31.78656+05:30
364	\N	doc-bd628377481b	2	done	0	2026-10-08 15:07:52.202129+05:30	2026-10-08 15:07:52.243225+05:30
365	\N	doc-eb33be1c8687	2	done	0	2026-10-08 15:07:56.439792+05:30	2026-10-08 15:07:56.475693+05:30
366	\N	doc-8405e29cdc24	2	done	0	2026-10-08 15:08:00.276502+05:30	2026-10-08 15:08:00.308049+05:30
367	\N	doc-43c0cbab0d45	2	done	0	2026-10-08 15:08:04.189431+05:30	2026-10-08 15:08:04.226832+05:30
368	\N	doc-a2d6def96248	2	done	0	2026-10-08 15:08:08.487346+05:30	2026-10-08 15:08:08.527442+05:30
369	\N	doc-fad3ce481e4b	2	done	0	2026-10-08 15:08:11.630865+05:30	2026-10-08 15:08:11.656744+05:30
370	\N	doc-0718297b71e4	3	done	0	2026-10-08 16:11:28.393903+05:30	2026-10-08 16:11:28.455238+05:30
371	\N	doc-de573a503f6d	3	done	0	2026-10-08 16:11:28.50201+05:30	2026-10-08 16:11:28.529061+05:30
372	\N	doc-03b90406eca2	3	done	0	2026-10-08 16:11:28.561501+05:30	2026-10-08 16:11:28.590314+05:30
373	\N	doc-0a51cdb40625	3	done	0	2026-10-08 16:11:28.622451+05:30	2026-10-08 16:11:28.634478+05:30
374	\N	doc-9a4395663625	3	done	0	2026-10-08 16:11:28.650898+05:30	2026-10-08 16:11:28.680844+05:30
375	\N	doc-becad9a82359	3	done	0	2026-10-08 16:11:28.713009+05:30	2026-10-08 16:11:28.743311+05:30
376	\N	doc-b02ac5215dad	3	done	0	2026-10-08 16:11:28.77472+05:30	2026-10-08 16:11:28.785665+05:30
377	\N	doc-37cea547ae24	3	done	0	2026-10-08 16:11:28.818854+05:30	2026-10-08 16:11:28.85158+05:30
378	\N	doc-5e4f6cd7d179	3	done	0	2026-10-08 16:11:28.881864+05:30	2026-10-08 16:11:28.918698+05:30
379	\N	doc-a453aa814971	3	done	0	2026-10-08 16:11:28.943644+05:30	2026-10-08 16:11:28.975447+05:30
380	\N	doc-e9cdba142890	3	done	0	2026-10-08 16:11:29.00724+05:30	2026-10-08 16:11:29.03472+05:30
381	\N	doc-bd628377481b	3	done	0	2026-10-08 16:11:29.050929+05:30	2026-10-08 16:11:29.064401+05:30
382	\N	doc-eb33be1c8687	3	done	0	2026-10-08 16:11:29.097599+05:30	2026-10-08 16:11:29.127091+05:30
383	\N	doc-8405e29cdc24	3	done	0	2026-10-08 16:11:29.166549+05:30	2026-10-08 16:11:29.20444+05:30
384	\N	doc-43c0cbab0d45	3	done	0	2026-10-08 16:11:29.23771+05:30	2026-10-08 16:11:29.266822+05:30
385	\N	doc-a2d6def96248	3	done	0	2026-10-08 16:11:29.302813+05:30	2026-10-08 16:11:29.331053+05:30
386	\N	doc-fad3ce481e4b	3	done	0	2026-10-08 16:11:29.384455+05:30	2026-10-08 16:11:29.422725+05:30
387	\N	doc-0718297b71e4	4	done	0	2026-10-09 03:43:06.521072+05:30	2026-10-09 03:43:06.583367+05:30
388	\N	doc-de573a503f6d	4	done	0	2026-10-09 03:43:06.644072+05:30	2026-10-09 03:43:06.668318+05:30
389	\N	doc-03b90406eca2	4	done	0	2026-10-09 03:43:06.722588+05:30	2026-10-09 03:43:06.736917+05:30
390	\N	doc-0a51cdb40625	4	done	0	2026-10-09 03:43:06.801088+05:30	2026-10-09 03:43:06.819227+05:30
391	\N	doc-9a4395663625	4	done	0	2026-10-09 03:43:06.847722+05:30	2026-10-09 03:43:06.873648+05:30
392	\N	doc-becad9a82359	4	done	0	2026-10-09 03:43:06.911301+05:30	2026-10-09 03:43:06.925147+05:30
393	\N	doc-b02ac5215dad	4	done	0	2026-10-09 03:43:06.980213+05:30	2026-10-09 03:43:07.01723+05:30
394	\N	doc-37cea547ae24	4	done	0	2026-10-09 03:43:07.047379+05:30	2026-10-09 03:43:07.075864+05:30
395	\N	doc-5e4f6cd7d179	4	done	0	2026-10-09 03:43:07.114225+05:30	2026-10-09 03:43:07.135888+05:30
396	\N	doc-a453aa814971	4	done	0	2026-10-09 03:43:07.176955+05:30	2026-10-09 03:43:07.192784+05:30
397	\N	doc-e9cdba142890	4	done	0	2026-10-09 03:43:07.225715+05:30	2026-10-09 03:43:07.244036+05:30
398	\N	doc-bd628377481b	4	done	0	2026-10-09 03:43:07.287471+05:30	2026-10-09 03:43:07.306008+05:30
399	\N	doc-eb33be1c8687	4	done	0	2026-10-09 03:43:07.351773+05:30	2026-10-09 03:43:07.38693+05:30
400	\N	doc-8405e29cdc24	4	done	0	2026-10-09 03:43:07.425336+05:30	2026-10-09 03:43:07.447907+05:30
401	\N	doc-43c0cbab0d45	4	done	0	2026-10-09 03:43:07.494247+05:30	2026-10-09 03:43:07.526667+05:30
402	\N	doc-a2d6def96248	4	done	0	2026-10-09 03:43:07.568782+05:30	2026-10-09 03:43:07.589548+05:30
403	\N	doc-fad3ce481e4b	4	done	0	2026-10-09 03:43:07.636473+05:30	2026-10-09 03:43:07.66868+05:30
404	\N	doc-0718297b71e4	5	done	0	2026-10-09 04:10:45.537362+05:30	2026-10-09 04:10:45.604419+05:30
405	\N	doc-de573a503f6d	5	done	0	2026-10-09 04:10:45.645671+05:30	2026-10-09 04:10:45.660426+05:30
406	\N	doc-03b90406eca2	5	done	0	2026-10-09 04:10:45.693703+05:30	2026-10-09 04:10:45.710055+05:30
407	\N	doc-0a51cdb40625	5	done	0	2026-10-09 04:10:45.758155+05:30	2026-10-09 04:10:45.784745+05:30
408	\N	doc-9a4395663625	5	done	0	2026-10-09 04:10:45.837291+05:30	2026-10-09 04:10:45.8566+05:30
409	\N	doc-becad9a82359	5	done	0	2026-10-09 04:10:45.90038+05:30	2026-10-09 04:10:45.91918+05:30
410	\N	doc-b02ac5215dad	5	done	0	2026-10-09 04:10:45.953811+05:30	2026-10-09 04:10:45.983161+05:30
411	\N	doc-37cea547ae24	5	done	0	2026-10-09 04:10:46.050355+05:30	2026-10-09 04:10:46.091656+05:30
412	\N	doc-5e4f6cd7d179	5	done	0	2026-10-09 04:10:46.17262+05:30	2026-10-09 04:10:46.202758+05:30
413	\N	doc-a453aa814971	5	done	0	2026-10-09 04:10:46.242033+05:30	2026-10-09 04:10:46.258018+05:30
414	\N	doc-e9cdba142890	5	done	0	2026-10-09 04:10:46.292181+05:30	2026-10-09 04:10:46.319479+05:30
476	\N	doc-de573a503f6d	9	done	0	2026-10-09 04:26:52.157382+05:30	2026-10-09 04:26:52.185798+05:30
415	\N	doc-bd628377481b	5	done	0	2026-10-09 04:10:46.377701+05:30	2026-10-09 04:10:46.421484+05:30
477	\N	doc-03b90406eca2	9	done	0	2026-10-09 04:26:52.232508+05:30	2026-10-09 04:26:52.246953+05:30
416	\N	doc-eb33be1c8687	5	done	0	2026-10-09 04:10:46.491569+05:30	2026-10-09 04:10:46.535459+05:30
478	\N	doc-0a51cdb40625	9	done	0	2026-10-09 04:26:52.275295+05:30	2026-10-09 04:26:52.321995+05:30
417	\N	doc-8405e29cdc24	5	done	0	2026-10-09 04:10:46.574664+05:30	2026-10-09 04:10:46.591995+05:30
479	\N	doc-9a4395663625	9	done	0	2026-10-09 04:26:52.353894+05:30	2026-10-09 04:26:52.407964+05:30
418	\N	doc-43c0cbab0d45	5	done	0	2026-10-09 04:10:46.658806+05:30	2026-10-09 04:10:46.705045+05:30
480	\N	doc-becad9a82359	9	done	0	2026-10-09 04:26:52.465219+05:30	2026-10-09 04:26:52.511919+05:30
419	\N	doc-a2d6def96248	5	done	0	2026-10-09 04:10:46.777667+05:30	2026-10-09 04:10:46.807827+05:30
481	\N	doc-b02ac5215dad	9	done	0	2026-10-09 04:26:52.560274+05:30	2026-10-09 04:26:52.602153+05:30
420	\N	doc-fad3ce481e4b	5	done	0	2026-10-09 04:10:46.869967+05:30	2026-10-09 04:10:46.884241+05:30
482	\N	doc-37cea547ae24	9	done	0	2026-10-09 04:26:52.653246+05:30	2026-10-09 04:26:52.695197+05:30
483	\N	doc-5e4f6cd7d179	9	done	0	2026-10-09 04:26:52.742163+05:30	2026-10-09 04:26:52.785139+05:30
422	\N	doc-0718297b71e4	6	done	0	2026-10-09 04:18:08.141807+05:30	2026-10-09 04:18:08.198227+05:30
484	\N	doc-a453aa814971	9	done	0	2026-10-09 04:26:52.837829+05:30	2026-10-09 04:26:52.879698+05:30
423	\N	doc-de573a503f6d	6	done	0	2026-10-09 04:18:08.269233+05:30	2026-10-09 04:18:08.293662+05:30
485	\N	doc-e9cdba142890	9	done	0	2026-10-09 04:26:52.927887+05:30	2026-10-09 04:26:52.974199+05:30
424	\N	doc-03b90406eca2	6	done	0	2026-10-09 04:18:08.33319+05:30	2026-10-09 04:18:08.373646+05:30
486	\N	doc-bd628377481b	9	done	0	2026-10-09 04:26:53.023156+05:30	2026-10-09 04:26:53.068981+05:30
425	\N	doc-0a51cdb40625	6	done	0	2026-10-09 04:18:08.418+05:30	2026-10-09 04:18:08.437109+05:30
487	\N	doc-eb33be1c8687	9	done	0	2026-10-09 04:26:53.13167+05:30	2026-10-09 04:26:53.176493+05:30
426	\N	doc-9a4395663625	6	done	0	2026-10-09 04:18:08.462143+05:30	2026-10-09 04:18:08.492367+05:30
488	\N	doc-8405e29cdc24	9	done	0	2026-10-09 04:26:53.213159+05:30	2026-10-09 04:26:53.254246+05:30
427	\N	doc-becad9a82359	6	done	0	2026-10-09 04:18:08.548788+05:30	2026-10-09 04:18:08.587947+05:30
489	\N	doc-43c0cbab0d45	9	done	0	2026-10-09 04:26:53.306084+05:30	2026-10-09 04:26:53.33532+05:30
428	\N	doc-b02ac5215dad	6	done	0	2026-10-09 04:18:08.641186+05:30	2026-10-09 04:18:08.679812+05:30
490	\N	doc-a2d6def96248	9	done	0	2026-10-09 04:26:53.37913+05:30	2026-10-09 04:26:53.424144+05:30
429	\N	doc-37cea547ae24	6	done	0	2026-10-09 04:18:08.715109+05:30	2026-10-09 04:18:08.761012+05:30
491	\N	doc-fad3ce481e4b	9	done	0	2026-10-09 04:26:53.455411+05:30	2026-10-09 04:26:53.485014+05:30
430	\N	doc-5e4f6cd7d179	6	done	0	2026-10-09 04:18:08.797264+05:30	2026-10-09 04:18:08.84523+05:30
630	\N	doc-0718297b71e4	18	done	0	2026-10-10 09:36:04.041985+05:30	2026-10-10 09:36:04.126618+05:30
431	\N	doc-a453aa814971	6	done	0	2026-10-09 04:18:08.882329+05:30	2026-10-09 04:18:08.906315+05:30
492	\N	doc-fad3ce481e4b	10	done	0	2026-10-09 04:31:51.318289+05:30	2026-10-09 04:31:51.400971+05:30
432	\N	doc-e9cdba142890	6	done	0	2026-10-09 04:18:08.936334+05:30	2026-10-09 04:18:08.971871+05:30
493	\N	doc-9a4395663625	10	done	0	2026-10-09 04:49:01.594771+05:30	2026-10-09 04:49:01.696113+05:30
433	\N	doc-bd628377481b	6	done	0	2026-10-09 04:18:09.054438+05:30	2026-10-09 04:18:09.079543+05:30
434	\N	doc-eb33be1c8687	6	done	0	2026-10-09 04:18:09.122079+05:30	2026-10-09 04:18:09.150615+05:30
494	\N	doc-0718297b71e4	10	done	0	2026-10-09 05:25:08.915225+05:30	2026-10-09 05:25:08.987973+05:30
435	\N	doc-8405e29cdc24	6	done	0	2026-10-09 04:18:09.168624+05:30	2026-10-09 04:18:09.195309+05:30
436	\N	doc-43c0cbab0d45	6	done	0	2026-10-09 04:18:09.228514+05:30	2026-10-09 04:18:09.241714+05:30
495	\N	doc-de573a503f6d	10	done	0	2026-10-09 05:25:09.037696+05:30	2026-10-09 05:25:09.094629+05:30
437	\N	doc-a2d6def96248	6	done	0	2026-10-09 04:18:09.274542+05:30	2026-10-09 04:18:09.302869+05:30
438	\N	doc-fad3ce481e4b	6	done	0	2026-10-09 04:18:09.337963+05:30	2026-10-09 04:18:09.368131+05:30
439	\N	doc-0718297b71e4	7	done	0	2026-10-09 04:19:47.979412+05:30	2026-10-09 04:19:48.033416+05:30
440	\N	doc-de573a503f6d	7	done	0	2026-10-09 04:19:48.084865+05:30	2026-10-09 04:19:48.130884+05:30
441	\N	doc-03b90406eca2	7	done	0	2026-10-09 04:19:48.195354+05:30	2026-10-09 04:19:48.249116+05:30
442	\N	doc-0a51cdb40625	7	done	0	2026-10-09 04:19:48.288723+05:30	2026-10-09 04:19:48.330184+05:30
443	\N	doc-9a4395663625	7	done	0	2026-10-09 04:19:48.363826+05:30	2026-10-09 04:19:48.421092+05:30
444	\N	doc-becad9a82359	7	done	0	2026-10-09 04:19:48.473073+05:30	2026-10-09 04:19:48.513056+05:30
445	\N	doc-b02ac5215dad	7	done	0	2026-10-09 04:19:48.563603+05:30	2026-10-09 04:19:48.610117+05:30
446	\N	doc-37cea547ae24	7	done	0	2026-10-09 04:19:48.657365+05:30	2026-10-09 04:19:48.688153+05:30
447	\N	doc-5e4f6cd7d179	7	done	0	2026-10-09 04:19:48.739684+05:30	2026-10-09 04:19:48.779064+05:30
448	\N	doc-a453aa814971	7	done	0	2026-10-09 04:19:48.817585+05:30	2026-10-09 04:19:48.858987+05:30
449	\N	doc-e9cdba142890	7	done	0	2026-10-09 04:19:48.907536+05:30	2026-10-09 04:19:48.951467+05:30
450	\N	doc-bd628377481b	7	done	0	2026-10-09 04:19:49.001649+05:30	2026-10-09 04:19:49.046256+05:30
451	\N	doc-eb33be1c8687	7	done	0	2026-10-09 04:19:49.075439+05:30	2026-10-09 04:19:49.121715+05:30
452	\N	doc-8405e29cdc24	7	done	0	2026-10-09 04:19:49.175731+05:30	2026-10-09 04:19:49.205938+05:30
453	\N	doc-43c0cbab0d45	7	done	0	2026-10-09 04:19:49.236262+05:30	2026-10-09 04:19:49.281232+05:30
454	\N	doc-a2d6def96248	7	done	0	2026-10-09 04:19:49.326456+05:30	2026-10-09 04:19:49.376055+05:30
455	\N	doc-fad3ce481e4b	7	done	0	2026-10-09 04:19:49.418607+05:30	2026-10-09 04:19:49.462099+05:30
456	\N	doc-15c4f8adcd3f	2	done	0	2026-10-09 04:23:11.863146+05:30	2026-10-09 04:23:11.916314+05:30
457	\N	doc-4f6b31669049	2	done	0	2026-10-09 04:23:12.666432+05:30	2026-10-09 04:23:12.684094+05:30
458	\N	doc-0718297b71e4	8	done	0	2026-10-09 04:24:43.044012+05:30	2026-10-09 04:24:43.103768+05:30
459	\N	doc-de573a503f6d	8	done	0	2026-10-09 04:24:43.154294+05:30	2026-10-09 04:24:43.196354+05:30
460	\N	doc-03b90406eca2	8	done	0	2026-10-09 04:24:43.223531+05:30	2026-10-09 04:24:43.259429+05:30
461	\N	doc-0a51cdb40625	8	done	0	2026-10-09 04:24:43.305913+05:30	2026-10-09 04:24:43.364988+05:30
462	\N	doc-9a4395663625	8	done	0	2026-10-09 04:24:43.413285+05:30	2026-10-09 04:24:43.447122+05:30
463	\N	doc-becad9a82359	8	done	0	2026-10-09 04:24:43.505209+05:30	2026-10-09 04:24:43.551292+05:30
464	\N	doc-b02ac5215dad	8	done	0	2026-10-09 04:24:43.598292+05:30	2026-10-09 04:24:43.631211+05:30
465	\N	doc-37cea547ae24	8	done	0	2026-10-09 04:24:43.666946+05:30	2026-10-09 04:24:43.707683+05:30
466	\N	doc-5e4f6cd7d179	8	done	0	2026-10-09 04:24:43.753864+05:30	2026-10-09 04:24:43.785538+05:30
467	\N	doc-a453aa814971	8	done	0	2026-10-09 04:24:43.831537+05:30	2026-10-09 04:24:43.878153+05:30
468	\N	doc-e9cdba142890	8	done	0	2026-10-09 04:24:43.896232+05:30	2026-10-09 04:24:43.941574+05:30
469	\N	doc-bd628377481b	8	done	0	2026-10-09 04:24:43.986701+05:30	2026-10-09 04:24:44.015687+05:30
470	\N	doc-eb33be1c8687	8	done	0	2026-10-09 04:24:44.064882+05:30	2026-10-09 04:24:44.110163+05:30
471	\N	doc-8405e29cdc24	8	done	0	2026-10-09 04:24:44.158693+05:30	2026-10-09 04:24:44.206164+05:30
472	\N	doc-43c0cbab0d45	8	done	0	2026-10-09 04:24:44.267416+05:30	2026-10-09 04:24:44.312417+05:30
473	\N	doc-a2d6def96248	8	done	0	2026-10-09 04:24:44.36728+05:30	2026-10-09 04:24:44.414279+05:30
474	\N	doc-fad3ce481e4b	8	done	0	2026-10-09 04:24:44.470204+05:30	2026-10-09 04:24:44.515273+05:30
496	\N	doc-03b90406eca2	10	done	0	2026-10-09 05:25:09.140709+05:30	2026-10-09 05:25:09.188887+05:30
497	\N	doc-0a51cdb40625	10	done	0	2026-10-09 05:25:09.222467+05:30	2026-10-09 05:25:09.268108+05:30
498	\N	doc-9a4395663625	11	done	0	2026-10-09 05:25:09.297561+05:30	2026-10-09 05:25:09.330408+05:30
499	\N	doc-becad9a82359	10	done	0	2026-10-09 05:25:09.351225+05:30	2026-10-09 05:25:09.393574+05:30
500	\N	doc-b02ac5215dad	10	done	0	2026-10-09 05:25:09.416611+05:30	2026-10-09 05:25:09.465968+05:30
501	\N	doc-37cea547ae24	10	done	0	2026-10-09 05:25:09.518448+05:30	2026-10-09 05:25:09.577425+05:30
502	\N	doc-5e4f6cd7d179	10	done	0	2026-10-09 05:25:09.620021+05:30	2026-10-09 05:25:09.654107+05:30
503	\N	doc-a453aa814971	10	done	0	2026-10-09 05:25:09.700224+05:30	2026-10-09 05:25:09.761033+05:30
504	\N	doc-e9cdba142890	10	done	0	2026-10-09 05:25:09.808952+05:30	2026-10-09 05:25:09.857939+05:30
505	\N	doc-bd628377481b	10	done	0	2026-10-09 05:25:09.925009+05:30	2026-10-09 05:25:09.950827+05:30
506	\N	doc-eb33be1c8687	10	done	0	2026-10-09 05:25:10.009665+05:30	2026-10-09 05:25:10.03485+05:30
507	\N	doc-8405e29cdc24	10	done	0	2026-10-09 05:25:10.083333+05:30	2026-10-09 05:25:10.129628+05:30
508	\N	doc-43c0cbab0d45	10	done	0	2026-10-09 05:25:10.165579+05:30	2026-10-09 05:25:10.194789+05:30
509	\N	doc-a2d6def96248	10	done	0	2026-10-09 05:25:10.238598+05:30	2026-10-09 05:25:10.283813+05:30
510	\N	doc-fad3ce481e4b	11	done	0	2026-10-09 05:25:10.331992+05:30	2026-10-09 05:25:10.36694+05:30
631	\N	doc-de573a503f6d	18	done	0	2026-10-10 09:36:04.178796+05:30	2026-10-10 09:36:04.250213+05:30
511	\N	doc-0718297b71e4	11	done	0	2026-10-09 05:27:13.209792+05:30	2026-10-09 05:27:13.311199+05:30
512	\N	doc-de573a503f6d	11	done	0	2026-10-09 05:27:13.414416+05:30	2026-10-09 05:27:13.490878+05:30
513	\N	doc-03b90406eca2	11	done	0	2026-10-09 05:27:13.549587+05:30	2026-10-09 05:27:13.598361+05:30
514	\N	doc-0a51cdb40625	11	done	0	2026-10-09 05:27:13.649908+05:30	2026-10-09 05:27:13.713101+05:30
515	\N	doc-9a4395663625	12	done	0	2026-10-09 05:27:13.794416+05:30	2026-10-09 05:27:13.861889+05:30
516	\N	doc-becad9a82359	11	done	0	2026-10-09 05:27:13.915075+05:30	2026-10-09 05:27:13.957064+05:30
517	\N	doc-b02ac5215dad	11	done	0	2026-10-09 05:27:13.990883+05:30	2026-10-09 05:27:14.031549+05:30
518	\N	doc-37cea547ae24	11	done	0	2026-10-09 05:27:14.093827+05:30	2026-10-09 05:27:14.161971+05:30
519	\N	doc-5e4f6cd7d179	11	done	0	2026-10-09 05:27:14.180762+05:30	2026-10-09 05:27:14.216894+05:30
520	\N	doc-a453aa814971	11	done	0	2026-10-09 05:27:14.270084+05:30	2026-10-09 05:27:14.31379+05:30
521	\N	doc-e9cdba142890	11	done	0	2026-10-09 05:27:14.364448+05:30	2026-10-09 05:27:14.389571+05:30
522	\N	doc-bd628377481b	11	done	0	2026-10-09 05:27:14.40718+05:30	2026-10-09 05:27:14.437196+05:30
523	\N	doc-eb33be1c8687	11	done	0	2026-10-09 05:27:14.500835+05:30	2026-10-09 05:27:14.544801+05:30
524	\N	doc-8405e29cdc24	11	done	0	2026-10-09 05:27:14.594536+05:30	2026-10-09 05:27:14.618651+05:30
525	\N	doc-43c0cbab0d45	11	done	0	2026-10-09 05:27:14.657101+05:30	2026-10-09 05:27:14.69795+05:30
526	\N	doc-a2d6def96248	11	done	0	2026-10-09 05:27:14.744422+05:30	2026-10-09 05:27:14.790578+05:30
527	\N	doc-fad3ce481e4b	12	done	0	2026-10-09 05:27:14.840574+05:30	2026-10-09 05:27:14.888878+05:30
528	\N	doc-0718297b71e4	12	done	0	2026-10-10 07:14:23.510862+05:30	2026-10-10 07:14:23.597292+05:30
529	\N	doc-de573a503f6d	12	done	0	2026-10-10 07:14:23.655742+05:30	2026-10-10 07:14:23.676809+05:30
530	\N	doc-03b90406eca2	12	done	0	2026-10-10 07:14:23.745456+05:30	2026-10-10 07:14:23.781715+05:30
531	\N	doc-0a51cdb40625	12	done	0	2026-10-10 07:14:23.837785+05:30	2026-10-10 07:14:23.887341+05:30
532	\N	doc-9a4395663625	13	done	0	2026-10-10 07:14:23.951419+05:30	2026-10-10 07:14:23.983171+05:30
533	\N	doc-becad9a82359	12	done	0	2026-10-10 07:14:24.070509+05:30	2026-10-10 07:14:24.119374+05:30
534	\N	doc-b02ac5215dad	12	done	0	2026-10-10 07:14:24.175092+05:30	2026-10-10 07:14:24.213207+05:30
535	\N	doc-37cea547ae24	12	done	0	2026-10-10 07:14:24.268481+05:30	2026-10-10 07:14:24.307797+05:30
536	\N	doc-5e4f6cd7d179	12	done	0	2026-10-10 07:14:24.353508+05:30	2026-10-10 07:14:24.39716+05:30
537	\N	doc-a453aa814971	12	done	0	2026-10-10 07:14:24.483301+05:30	2026-10-10 07:14:24.521876+05:30
538	\N	doc-e9cdba142890	12	done	0	2026-10-10 07:14:24.585086+05:30	2026-10-10 07:14:24.638463+05:30
539	\N	doc-bd628377481b	12	done	0	2026-10-10 07:14:24.695437+05:30	2026-10-10 07:14:24.750379+05:30
540	\N	doc-eb33be1c8687	12	done	0	2026-10-10 07:14:24.798922+05:30	2026-10-10 07:14:24.836481+05:30
541	\N	doc-8405e29cdc24	12	done	0	2026-10-10 07:14:24.877459+05:30	2026-10-10 07:14:24.928689+05:30
542	\N	doc-43c0cbab0d45	12	done	0	2026-10-10 07:14:24.991265+05:30	2026-10-10 07:14:25.024369+05:30
543	\N	doc-a2d6def96248	12	done	0	2026-10-10 07:14:25.08285+05:30	2026-10-10 07:14:25.121291+05:30
544	\N	doc-fad3ce481e4b	13	done	0	2026-10-10 07:14:25.180883+05:30	2026-10-10 07:14:25.233011+05:30
545	\N	doc-0718297b71e4	13	done	0	2026-10-10 09:06:27.831671+05:30	2026-10-10 09:06:27.902304+05:30
546	\N	doc-de573a503f6d	13	done	0	2026-10-10 09:06:28.035714+05:30	2026-10-10 09:06:28.122362+05:30
547	\N	doc-03b90406eca2	13	done	0	2026-10-10 09:06:28.222651+05:30	2026-10-10 09:06:28.310723+05:30
548	\N	doc-0a51cdb40625	13	done	0	2026-10-10 09:06:28.382005+05:30	2026-10-10 09:06:28.431637+05:30
549	\N	doc-9a4395663625	14	done	0	2026-10-10 09:06:28.547743+05:30	2026-10-10 09:06:28.606989+05:30
550	\N	doc-becad9a82359	13	done	0	2026-10-10 09:06:28.681419+05:30	2026-10-10 09:06:28.762945+05:30
551	\N	doc-b02ac5215dad	13	done	0	2026-10-10 09:06:28.836841+05:30	2026-10-10 09:06:28.912474+05:30
552	\N	doc-37cea547ae24	13	done	0	2026-10-10 09:06:29.020781+05:30	2026-10-10 09:06:29.106622+05:30
553	\N	doc-5e4f6cd7d179	13	done	0	2026-10-10 09:06:29.22785+05:30	2026-10-10 09:06:29.302301+05:30
554	\N	doc-a453aa814971	13	done	0	2026-10-10 09:06:29.387678+05:30	2026-10-10 09:06:29.453136+05:30
555	\N	doc-e9cdba142890	13	done	0	2026-10-10 09:06:29.562686+05:30	2026-10-10 09:06:29.625379+05:30
556	\N	doc-bd628377481b	13	done	0	2026-10-10 09:06:29.725435+05:30	2026-10-10 09:06:29.755703+05:30
557	\N	doc-eb33be1c8687	13	done	0	2026-10-10 09:06:29.810719+05:30	2026-10-10 09:06:29.888838+05:30
558	\N	doc-8405e29cdc24	13	done	0	2026-10-10 09:06:29.991294+05:30	2026-10-10 09:06:30.040199+05:30
559	\N	doc-43c0cbab0d45	13	done	0	2026-10-10 09:06:30.124836+05:30	2026-10-10 09:06:30.180002+05:30
560	\N	doc-a2d6def96248	13	done	0	2026-10-10 09:06:30.223717+05:30	2026-10-10 09:06:30.256259+05:30
561	\N	doc-fad3ce481e4b	14	done	0	2026-10-10 09:06:30.32914+05:30	2026-10-10 09:06:30.408252+05:30
562	\N	doc-0718297b71e4	14	done	0	2026-10-10 09:16:28.107622+05:30	2026-10-10 09:16:28.173498+05:30
563	\N	doc-de573a503f6d	14	done	0	2026-10-10 09:16:28.22453+05:30	2026-10-10 09:16:28.266119+05:30
564	\N	doc-03b90406eca2	14	done	0	2026-10-10 09:16:28.311712+05:30	2026-10-10 09:16:28.355421+05:30
565	\N	doc-0a51cdb40625	14	done	0	2026-10-10 09:16:28.407023+05:30	2026-10-10 09:16:28.435078+05:30
566	\N	doc-9a4395663625	15	done	0	2026-10-10 09:16:28.472427+05:30	2026-10-10 09:16:28.512516+05:30
567	\N	doc-becad9a82359	14	done	0	2026-10-10 09:16:28.555841+05:30	2026-10-10 09:16:28.591793+05:30
568	\N	doc-b02ac5215dad	14	done	0	2026-10-10 09:16:28.637903+05:30	2026-10-10 09:16:28.684614+05:30
569	\N	doc-37cea547ae24	14	done	0	2026-10-10 09:16:28.732828+05:30	2026-10-10 09:16:28.777022+05:30
570	\N	doc-5e4f6cd7d179	14	done	0	2026-10-10 09:16:28.807421+05:30	2026-10-10 09:16:28.854865+05:30
571	\N	doc-a453aa814971	14	done	0	2026-10-10 09:16:28.908183+05:30	2026-10-10 09:16:28.939716+05:30
572	\N	doc-e9cdba142890	14	done	0	2026-10-10 09:16:29.001448+05:30	2026-10-10 09:16:29.056924+05:30
573	\N	doc-bd628377481b	14	done	0	2026-10-10 09:16:29.105275+05:30	2026-10-10 09:16:29.168461+05:30
813	\N	doc-50690e9459bb	3	done	0	2026-10-10 10:35:50.351366+05:30	2026-10-10 10:35:50.439035+05:30
574	\N	doc-eb33be1c8687	14	done	0	2026-10-10 09:16:29.216061+05:30	2026-10-10 09:16:29.257992+05:30
632	\N	doc-03b90406eca2	18	done	0	2026-10-10 09:36:04.303451+05:30	2026-10-10 09:36:04.36233+05:30
575	\N	doc-8405e29cdc24	14	done	0	2026-10-10 09:16:29.303397+05:30	2026-10-10 09:16:29.371404+05:30
633	\N	doc-0a51cdb40625	18	done	0	2026-10-10 09:36:04.411734+05:30	2026-10-10 09:36:04.444976+05:30
576	\N	doc-43c0cbab0d45	14	done	0	2026-10-10 09:16:29.415898+05:30	2026-10-10 09:16:29.457046+05:30
577	\N	doc-a2d6def96248	14	done	0	2026-10-10 09:16:29.493159+05:30	2026-10-10 09:16:29.521762+05:30
634	\N	doc-9a4395663625	19	done	0	2026-10-10 09:36:04.510552+05:30	2026-10-10 09:36:04.580672+05:30
578	\N	doc-fad3ce481e4b	15	done	0	2026-10-10 09:16:29.570516+05:30	2026-10-10 09:16:29.613043+05:30
635	\N	doc-becad9a82359	18	done	0	2026-10-10 09:36:04.634101+05:30	2026-10-10 09:36:04.664014+05:30
579	\N	doc-0718297b71e4	15	done	0	2026-10-10 09:21:53.258427+05:30	2026-10-10 09:21:53.312498+05:30
580	\N	doc-de573a503f6d	15	done	0	2026-10-10 09:21:53.37638+05:30	2026-10-10 09:21:53.419494+05:30
636	\N	doc-b02ac5215dad	18	done	0	2026-10-10 09:36:04.713358+05:30	2026-10-10 09:36:04.760978+05:30
581	\N	doc-03b90406eca2	15	done	0	2026-10-10 09:21:53.463804+05:30	2026-10-10 09:21:53.509572+05:30
637	\N	doc-37cea547ae24	18	done	0	2026-10-10 09:36:04.810743+05:30	2026-10-10 09:36:04.834513+05:30
582	\N	doc-0a51cdb40625	15	done	0	2026-10-10 09:21:53.557743+05:30	2026-10-10 09:21:53.604075+05:30
583	\N	doc-9a4395663625	16	done	0	2026-10-10 09:21:53.640897+05:30	2026-10-10 09:21:53.667646+05:30
638	\N	doc-5e4f6cd7d179	18	done	0	2026-10-10 09:36:04.872634+05:30	2026-10-10 09:36:04.925534+05:30
584	\N	doc-becad9a82359	15	done	0	2026-10-10 09:21:53.710082+05:30	2026-10-10 09:21:53.755111+05:30
639	\N	doc-a453aa814971	18	done	0	2026-10-10 09:36:04.975046+05:30	2026-10-10 09:36:05.005357+05:30
585	\N	doc-b02ac5215dad	15	done	0	2026-10-10 09:21:53.800265+05:30	2026-10-10 09:21:53.841093+05:30
586	\N	doc-37cea547ae24	15	done	0	2026-10-10 09:21:53.898112+05:30	2026-10-10 09:21:53.943814+05:30
640	\N	doc-e9cdba142890	18	done	0	2026-10-10 09:36:05.053808+05:30	2026-10-10 09:36:05.12419+05:30
587	\N	doc-5e4f6cd7d179	15	done	0	2026-10-10 09:21:53.981984+05:30	2026-10-10 09:21:54.024785+05:30
641	\N	doc-bd628377481b	18	done	0	2026-10-10 09:36:05.16062+05:30	2026-10-10 09:36:05.204976+05:30
588	\N	doc-a453aa814971	15	done	0	2026-10-10 09:21:54.071287+05:30	2026-10-10 09:21:54.135116+05:30
589	\N	doc-e9cdba142890	15	done	0	2026-10-10 09:21:54.194037+05:30	2026-10-10 09:21:54.219334+05:30
642	\N	doc-eb33be1c8687	18	done	0	2026-10-10 09:36:05.233429+05:30	2026-10-10 09:36:05.25854+05:30
590	\N	doc-bd628377481b	15	done	0	2026-10-10 09:21:54.25136+05:30	2026-10-10 09:21:54.290297+05:30
643	\N	doc-8405e29cdc24	18	done	0	2026-10-10 09:36:05.284118+05:30	2026-10-10 09:36:05.305656+05:30
591	\N	doc-eb33be1c8687	15	done	0	2026-10-10 09:21:54.338856+05:30	2026-10-10 09:21:54.380283+05:30
592	\N	doc-8405e29cdc24	15	done	0	2026-10-10 09:21:54.422756+05:30	2026-10-10 09:21:54.497594+05:30
644	\N	doc-43c0cbab0d45	18	done	0	2026-10-10 09:36:05.334521+05:30	2026-10-10 09:36:05.355857+05:30
593	\N	doc-43c0cbab0d45	15	done	0	2026-10-10 09:21:54.548261+05:30	2026-10-10 09:21:54.593201+05:30
645	\N	doc-a2d6def96248	18	done	0	2026-10-10 09:36:05.399313+05:30	2026-10-10 09:36:05.41869+05:30
594	\N	doc-a2d6def96248	15	done	0	2026-10-10 09:21:54.639803+05:30	2026-10-10 09:21:54.680831+05:30
595	\N	doc-fad3ce481e4b	16	done	0	2026-10-10 09:21:54.73332+05:30	2026-10-10 09:21:54.763511+05:30
646	\N	doc-fad3ce481e4b	19	done	0	2026-10-10 09:36:05.446589+05:30	2026-10-10 09:36:05.491656+05:30
596	\N	doc-0718297b71e4	16	done	0	2026-10-10 09:24:15.237982+05:30	2026-10-10 09:24:15.301292+05:30
597	\N	doc-de573a503f6d	16	done	0	2026-10-10 09:24:15.356177+05:30	2026-10-10 09:24:15.39718+05:30
647	\N	doc-0718297b71e4	19	done	0	2026-10-10 10:02:55.226426+05:30	2026-10-10 10:02:55.273141+05:30
598	\N	doc-03b90406eca2	16	done	0	2026-10-10 09:24:15.446386+05:30	2026-10-10 09:24:15.475521+05:30
599	\N	doc-0a51cdb40625	16	done	0	2026-10-10 09:24:15.504289+05:30	2026-10-10 09:24:15.553177+05:30
648	\N	doc-de573a503f6d	19	done	0	2026-10-10 10:02:55.322819+05:30	2026-10-10 10:02:55.366352+05:30
600	\N	doc-9a4395663625	17	done	0	2026-10-10 09:24:15.603057+05:30	2026-10-10 09:24:15.647751+05:30
601	\N	doc-becad9a82359	16	done	0	2026-10-10 09:24:15.694885+05:30	2026-10-10 09:24:15.718846+05:30
649	\N	doc-03b90406eca2	19	done	0	2026-10-10 10:02:55.414785+05:30	2026-10-10 10:02:55.46051+05:30
602	\N	doc-b02ac5215dad	16	done	0	2026-10-10 09:24:15.800109+05:30	2026-10-10 09:24:15.860392+05:30
603	\N	doc-37cea547ae24	16	done	0	2026-10-10 09:24:15.907935+05:30	2026-10-10 09:24:15.952576+05:30
650	\N	doc-0a51cdb40625	19	done	0	2026-10-10 10:02:55.50595+05:30	2026-10-10 10:02:55.551094+05:30
604	\N	doc-5e4f6cd7d179	16	done	0	2026-10-10 09:24:16.006487+05:30	2026-10-10 09:24:16.077679+05:30
605	\N	doc-a453aa814971	16	done	0	2026-10-10 09:24:16.129287+05:30	2026-10-10 09:24:16.170596+05:30
651	\N	doc-9a4395663625	20	done	0	2026-10-10 10:02:55.599691+05:30	2026-10-10 10:02:55.635008+05:30
606	\N	doc-e9cdba142890	16	done	0	2026-10-10 09:24:16.221601+05:30	2026-10-10 09:24:16.252175+05:30
607	\N	doc-bd628377481b	16	done	0	2026-10-10 09:24:16.29948+05:30	2026-10-10 09:24:16.347668+05:30
652	\N	doc-becad9a82359	19	done	0	2026-10-10 10:02:55.663671+05:30	2026-10-10 10:02:55.707068+05:30
608	\N	doc-eb33be1c8687	16	done	0	2026-10-10 09:24:16.409062+05:30	2026-10-10 09:24:16.451538+05:30
609	\N	doc-8405e29cdc24	16	done	0	2026-10-10 09:24:16.50253+05:30	2026-10-10 09:24:16.533167+05:30
653	\N	doc-b02ac5215dad	19	done	0	2026-10-10 10:02:55.755255+05:30	2026-10-10 10:02:55.784741+05:30
610	\N	doc-43c0cbab0d45	16	done	0	2026-10-10 09:24:16.579456+05:30	2026-10-10 09:24:16.622666+05:30
611	\N	doc-a2d6def96248	16	done	0	2026-10-10 09:24:16.672344+05:30	2026-10-10 09:24:16.707946+05:30
654	\N	doc-37cea547ae24	19	done	0	2026-10-10 10:02:55.836966+05:30	2026-10-10 10:02:55.864046+05:30
612	\N	doc-fad3ce481e4b	17	done	0	2026-10-10 09:24:16.76994+05:30	2026-10-10 09:24:16.807898+05:30
613	\N	doc-0718297b71e4	17	done	0	2026-10-10 09:32:44.524965+05:30	2026-10-10 09:32:44.609576+05:30
614	\N	doc-de573a503f6d	17	done	0	2026-10-10 09:32:44.682826+05:30	2026-10-10 09:32:44.723216+05:30
615	\N	doc-03b90406eca2	17	done	0	2026-10-10 09:32:44.773122+05:30	2026-10-10 09:32:44.800663+05:30
616	\N	doc-0a51cdb40625	17	done	0	2026-10-10 09:32:44.876174+05:30	2026-10-10 09:32:44.906388+05:30
617	\N	doc-9a4395663625	18	done	0	2026-10-10 09:32:44.929573+05:30	2026-10-10 09:32:44.983123+05:30
618	\N	doc-becad9a82359	17	done	0	2026-10-10 09:32:45.049756+05:30	2026-10-10 09:32:45.091367+05:30
619	\N	doc-b02ac5215dad	17	done	0	2026-10-10 09:32:45.139167+05:30	2026-10-10 09:32:45.183942+05:30
620	\N	doc-37cea547ae24	17	done	0	2026-10-10 09:32:45.238071+05:30	2026-10-10 09:32:45.309163+05:30
621	\N	doc-5e4f6cd7d179	17	done	0	2026-10-10 09:32:45.355952+05:30	2026-10-10 09:32:45.387019+05:30
622	\N	doc-a453aa814971	17	done	0	2026-10-10 09:32:45.436941+05:30	2026-10-10 09:32:45.482482+05:30
623	\N	doc-e9cdba142890	17	done	0	2026-10-10 09:32:45.533222+05:30	2026-10-10 09:32:45.583581+05:30
624	\N	doc-bd628377481b	17	done	0	2026-10-10 09:32:45.638171+05:30	2026-10-10 09:32:45.682958+05:30
625	\N	doc-eb33be1c8687	17	done	0	2026-10-10 09:32:45.746002+05:30	2026-10-10 09:32:45.799614+05:30
626	\N	doc-8405e29cdc24	17	done	0	2026-10-10 09:32:45.8718+05:30	2026-10-10 09:32:45.917921+05:30
627	\N	doc-43c0cbab0d45	17	done	0	2026-10-10 09:32:45.959239+05:30	2026-10-10 09:32:46.028473+05:30
628	\N	doc-a2d6def96248	17	done	0	2026-10-10 09:32:46.078623+05:30	2026-10-10 09:32:46.121194+05:30
629	\N	doc-fad3ce481e4b	18	done	0	2026-10-10 09:32:46.155466+05:30	2026-10-10 09:32:46.185081+05:30
655	\N	doc-5e4f6cd7d179	19	done	0	2026-10-10 10:02:55.914629+05:30	2026-10-10 10:02:55.957635+05:30
656	\N	doc-a453aa814971	19	done	0	2026-10-10 10:02:56.00478+05:30	2026-10-10 10:02:56.070723+05:30
657	\N	doc-e9cdba142890	19	done	0	2026-10-10 10:02:56.115574+05:30	2026-10-10 10:02:56.160554+05:30
658	\N	doc-bd628377481b	19	done	0	2026-10-10 10:02:56.187458+05:30	2026-10-10 10:02:56.239052+05:30
659	\N	doc-eb33be1c8687	19	done	0	2026-10-10 10:02:56.301522+05:30	2026-10-10 10:02:56.332881+05:30
660	\N	doc-8405e29cdc24	19	done	0	2026-10-10 10:02:56.373624+05:30	2026-10-10 10:02:56.418948+05:30
661	\N	doc-43c0cbab0d45	19	done	0	2026-10-10 10:02:56.470376+05:30	2026-10-10 10:02:56.499102+05:30
829	\N	doc-50690e9459bb	4	done	0	2026-10-10 11:01:57.000526+05:30	2026-10-10 11:01:57.05602+05:30
662	\N	doc-a2d6def96248	19	done	0	2026-10-10 10:02:56.54827+05:30	2026-10-10 10:02:56.59401+05:30
663	\N	doc-fad3ce481e4b	20	done	0	2026-10-10 10:02:56.642231+05:30	2026-10-10 10:02:56.671122+05:30
664	\N	doc-0718297b71e4	20	done	0	2026-10-10 10:07:30.922164+05:30	2026-10-10 10:07:30.990027+05:30
665	\N	doc-de573a503f6d	20	done	0	2026-10-10 10:07:31.058605+05:30	2026-10-10 10:07:31.106786+05:30
666	\N	doc-03b90406eca2	20	done	0	2026-10-10 10:07:31.161282+05:30	2026-10-10 10:07:31.189549+05:30
667	\N	doc-0a51cdb40625	20	done	0	2026-10-10 10:07:31.236679+05:30	2026-10-10 10:07:31.277497+05:30
668	\N	doc-9a4395663625	21	done	0	2026-10-10 10:07:31.324931+05:30	2026-10-10 10:07:31.3595+05:30
669	\N	doc-becad9a82359	20	done	0	2026-10-10 10:07:31.40589+05:30	2026-10-10 10:07:31.454559+05:30
670	\N	doc-b02ac5215dad	20	done	0	2026-10-10 10:07:31.497927+05:30	2026-10-10 10:07:31.540859+05:30
671	\N	doc-37cea547ae24	20	done	0	2026-10-10 10:07:31.573093+05:30	2026-10-10 10:07:31.638204+05:30
672	\N	doc-5e4f6cd7d179	20	done	0	2026-10-10 10:07:31.686892+05:30	2026-10-10 10:07:31.727172+05:30
673	\N	doc-a453aa814971	20	done	0	2026-10-10 10:07:31.774485+05:30	2026-10-10 10:07:31.838159+05:30
674	\N	doc-e9cdba142890	20	done	0	2026-10-10 10:07:31.873134+05:30	2026-10-10 10:07:31.913267+05:30
675	\N	doc-bd628377481b	20	done	0	2026-10-10 10:07:31.961197+05:30	2026-10-10 10:07:32.005048+05:30
676	\N	doc-eb33be1c8687	20	done	0	2026-10-10 10:07:32.07292+05:30	2026-10-10 10:07:32.11434+05:30
677	\N	doc-8405e29cdc24	20	done	0	2026-10-10 10:07:32.163423+05:30	2026-10-10 10:07:32.207198+05:30
678	\N	doc-43c0cbab0d45	20	done	0	2026-10-10 10:07:32.244906+05:30	2026-10-10 10:07:32.300134+05:30
679	\N	doc-a2d6def96248	20	done	0	2026-10-10 10:07:32.351499+05:30	2026-10-10 10:07:32.394427+05:30
680	\N	doc-fad3ce481e4b	21	done	0	2026-10-10 10:07:32.429985+05:30	2026-10-10 10:07:32.447929+05:30
681	\N	doc-0718297b71e4	21	done	0	2026-10-10 10:10:43.214294+05:30	2026-10-10 10:10:43.314722+05:30
682	\N	doc-de573a503f6d	21	done	0	2026-10-10 10:10:43.354032+05:30	2026-10-10 10:10:43.407694+05:30
683	\N	doc-03b90406eca2	21	done	0	2026-10-10 10:10:43.50549+05:30	2026-10-10 10:10:43.583466+05:30
684	\N	doc-0a51cdb40625	21	done	0	2026-10-10 10:10:43.683055+05:30	2026-10-10 10:10:43.749232+05:30
685	\N	doc-9a4395663625	22	done	0	2026-10-10 10:10:43.839135+05:30	2026-10-10 10:10:43.926027+05:30
686	\N	doc-becad9a82359	21	done	0	2026-10-10 10:10:44.022218+05:30	2026-10-10 10:10:44.082811+05:30
687	\N	doc-b02ac5215dad	21	done	0	2026-10-10 10:10:44.146924+05:30	2026-10-10 10:10:44.222461+05:30
688	\N	doc-37cea547ae24	21	done	0	2026-10-10 10:10:44.320197+05:30	2026-10-10 10:10:44.37092+05:30
689	\N	doc-5e4f6cd7d179	21	done	0	2026-10-10 10:10:44.465876+05:30	2026-10-10 10:10:44.542682+05:30
690	\N	doc-a453aa814971	21	done	0	2026-10-10 10:10:44.615174+05:30	2026-10-10 10:10:44.701658+05:30
691	\N	doc-e9cdba142890	21	done	0	2026-10-10 10:10:44.796751+05:30	2026-10-10 10:10:44.873159+05:30
692	\N	doc-bd628377481b	21	done	0	2026-10-10 10:10:44.965018+05:30	2026-10-10 10:10:45.024004+05:30
693	\N	doc-eb33be1c8687	21	done	0	2026-10-10 10:10:45.078635+05:30	2026-10-10 10:10:45.170013+05:30
694	\N	doc-8405e29cdc24	21	done	0	2026-10-10 10:10:45.263147+05:30	2026-10-10 10:10:45.338418+05:30
695	\N	doc-43c0cbab0d45	21	done	0	2026-10-10 10:10:45.40463+05:30	2026-10-10 10:10:45.483682+05:30
696	\N	doc-a2d6def96248	21	done	0	2026-10-10 10:10:45.58241+05:30	2026-10-10 10:10:45.672791+05:30
697	\N	doc-fad3ce481e4b	22	done	0	2026-10-10 10:10:45.748857+05:30	2026-10-10 10:10:45.803406+05:30
698	\N	doc-0718297b71e4	22	done	0	2026-10-10 10:20:42.986323+05:30	2026-10-10 10:20:43.053372+05:30
699	\N	doc-de573a503f6d	22	done	0	2026-10-10 10:20:43.102242+05:30	2026-10-10 10:20:43.150021+05:30
700	\N	doc-03b90406eca2	22	done	0	2026-10-10 10:20:43.193011+05:30	2026-10-10 10:20:43.239913+05:30
701	\N	doc-0a51cdb40625	22	done	0	2026-10-10 10:20:43.285867+05:30	2026-10-10 10:20:43.328609+05:30
702	\N	doc-9a4395663625	23	done	0	2026-10-10 10:20:43.377579+05:30	2026-10-10 10:20:43.42504+05:30
703	\N	doc-becad9a82359	22	done	0	2026-10-10 10:20:43.476515+05:30	2026-10-10 10:20:43.523908+05:30
704	\N	doc-b02ac5215dad	22	done	0	2026-10-10 10:20:43.566669+05:30	2026-10-10 10:20:43.613079+05:30
705	\N	doc-37cea547ae24	22	done	0	2026-10-10 10:20:43.659545+05:30	2026-10-10 10:20:43.695261+05:30
706	\N	doc-5e4f6cd7d179	22	done	0	2026-10-10 10:20:43.740803+05:30	2026-10-10 10:20:43.782798+05:30
707	\N	doc-a453aa814971	22	done	0	2026-10-10 10:20:43.848708+05:30	2026-10-10 10:20:43.894408+05:30
708	\N	doc-e9cdba142890	22	done	0	2026-10-10 10:20:43.948156+05:30	2026-10-10 10:20:43.98859+05:30
709	\N	doc-bd628377481b	22	done	0	2026-10-10 10:20:44.035828+05:30	2026-10-10 10:20:44.068063+05:30
710	\N	doc-eb33be1c8687	22	done	0	2026-10-10 10:20:44.099294+05:30	2026-10-10 10:20:44.139615+05:30
711	\N	doc-8405e29cdc24	22	done	0	2026-10-10 10:20:44.190623+05:30	2026-10-10 10:20:44.234583+05:30
712	\N	doc-43c0cbab0d45	22	done	0	2026-10-10 10:20:44.285058+05:30	2026-10-10 10:20:44.31617+05:30
713	\N	doc-a2d6def96248	22	done	0	2026-10-10 10:20:44.363993+05:30	2026-10-10 10:20:44.407599+05:30
714	\N	doc-fad3ce481e4b	23	done	0	2026-10-10 10:20:44.442031+05:30	2026-10-10 10:20:44.488007+05:30
715	\N	doc-0718297b71e4	23	done	0	2026-10-10 10:22:32.559935+05:30	2026-10-10 10:22:32.602202+05:30
716	\N	doc-de573a503f6d	23	done	0	2026-10-10 10:22:32.652281+05:30	2026-10-10 10:22:32.705724+05:30
717	\N	doc-03b90406eca2	23	done	0	2026-10-10 10:22:32.757126+05:30	2026-10-10 10:22:32.814227+05:30
718	\N	doc-0a51cdb40625	23	done	0	2026-10-10 10:22:32.876098+05:30	2026-10-10 10:22:32.93637+05:30
719	\N	doc-9a4395663625	24	done	0	2026-10-10 10:22:32.992603+05:30	2026-10-10 10:22:33.054469+05:30
720	\N	doc-becad9a82359	23	done	0	2026-10-10 10:22:33.088698+05:30	2026-10-10 10:22:33.139912+05:30
721	\N	doc-b02ac5215dad	23	done	0	2026-10-10 10:22:33.193677+05:30	2026-10-10 10:22:33.234526+05:30
722	\N	doc-37cea547ae24	23	done	0	2026-10-10 10:22:33.290543+05:30	2026-10-10 10:22:33.345347+05:30
723	\N	doc-5e4f6cd7d179	23	done	0	2026-10-10 10:22:33.388121+05:30	2026-10-10 10:22:33.417492+05:30
724	\N	doc-a453aa814971	23	done	0	2026-10-10 10:22:33.455652+05:30	2026-10-10 10:22:33.496906+05:30
725	\N	doc-e9cdba142890	23	done	0	2026-10-10 10:22:33.544973+05:30	2026-10-10 10:22:33.589969+05:30
726	\N	doc-bd628377481b	23	done	0	2026-10-10 10:22:33.637629+05:30	2026-10-10 10:22:33.686066+05:30
727	\N	doc-eb33be1c8687	23	done	0	2026-10-10 10:22:33.734063+05:30	2026-10-10 10:22:33.76732+05:30
728	\N	doc-8405e29cdc24	23	done	0	2026-10-10 10:22:33.811442+05:30	2026-10-10 10:22:33.843631+05:30
729	\N	doc-43c0cbab0d45	23	done	0	2026-10-10 10:22:33.889169+05:30	2026-10-10 10:22:33.922167+05:30
730	\N	doc-a2d6def96248	23	done	0	2026-10-10 10:22:33.96746+05:30	2026-10-10 10:22:34.011886+05:30
731	\N	doc-fad3ce481e4b	24	done	0	2026-10-10 10:22:34.046973+05:30	2026-10-10 10:22:34.089719+05:30
814	\N	doc-6c4fc0bf754c	3	done	0	2026-10-10 10:35:53.953078+05:30	2026-10-10 10:35:54.010388+05:30
732	\N	doc-0718297b71e4	24	done	0	2026-10-10 10:25:55.144883+05:30	2026-10-10 10:25:55.212144+05:30
817	\N	doc-e8e98b8c83a3	3	done	0	2026-10-10 10:36:04.566008+05:30	2026-10-10 10:36:04.590803+05:30
733	\N	doc-de573a503f6d	24	done	0	2026-10-10 10:25:55.262556+05:30	2026-10-10 10:25:55.287002+05:30
820	\N	doc-98940217eca3	3	done	0	2026-10-10 10:36:14.011512+05:30	2026-10-10 10:36:14.087733+05:30
734	\N	doc-03b90406eca2	24	done	0	2026-10-10 10:25:55.334912+05:30	2026-10-10 10:25:55.363381+05:30
823	\N	doc-d6402dc16e20	3	done	0	2026-10-10 10:36:24.778175+05:30	2026-10-10 10:36:24.815531+05:30
735	\N	doc-0a51cdb40625	24	done	0	2026-10-10 10:25:55.400662+05:30	2026-10-10 10:25:55.428102+05:30
826	\N	doc-95f9bf76e643	3	done	0	2026-10-10 10:36:34.647005+05:30	2026-10-10 10:36:34.670057+05:30
736	\N	doc-9a4395663625	25	done	0	2026-10-10 10:25:55.479163+05:30	2026-10-10 10:25:55.522243+05:30
737	\N	doc-becad9a82359	24	done	0	2026-10-10 10:25:55.568902+05:30	2026-10-10 10:25:55.615833+05:30
830	\N	doc-6c4fc0bf754c	4	done	0	2026-10-10 11:02:00.658812+05:30	2026-10-10 11:02:00.708569+05:30
738	\N	doc-b02ac5215dad	24	done	0	2026-10-10 10:25:55.665438+05:30	2026-10-10 10:25:55.709273+05:30
739	\N	doc-37cea547ae24	24	done	0	2026-10-10 10:25:55.760215+05:30	2026-10-10 10:25:55.792674+05:30
837	\N	doc-75f8446029de	4	done	0	2026-10-10 11:02:15.966544+05:30	2026-10-10 11:02:16.015482+05:30
740	\N	doc-5e4f6cd7d179	24	done	0	2026-10-10 10:25:55.848866+05:30	2026-10-10 10:25:55.893425+05:30
741	\N	doc-a453aa814971	24	done	0	2026-10-10 10:25:55.943629+05:30	2026-10-10 10:25:55.985925+05:30
841	\N	doc-98940217eca3	4	done	0	2026-10-10 11:02:23.481904+05:30	2026-10-10 11:02:23.528436+05:30
742	\N	doc-e9cdba142890	24	done	0	2026-10-10 10:25:56.03469+05:30	2026-10-10 10:25:56.082047+05:30
743	\N	doc-bd628377481b	24	done	0	2026-10-10 10:25:56.122778+05:30	2026-10-10 10:25:56.175632+05:30
744	\N	doc-eb33be1c8687	24	done	0	2026-10-10 10:25:56.220823+05:30	2026-10-10 10:25:56.266135+05:30
745	\N	doc-8405e29cdc24	24	done	0	2026-10-10 10:25:56.316444+05:30	2026-10-10 10:25:56.362877+05:30
746	\N	doc-43c0cbab0d45	24	done	0	2026-10-10 10:25:56.412643+05:30	2026-10-10 10:25:56.452477+05:30
852	\N	doc-98940217eca3	5	done	0	2026-10-10 11:02:32.352468+05:30	2026-10-10 11:02:32.39778+05:30
747	\N	doc-a2d6def96248	24	done	0	2026-10-10 10:25:56.500291+05:30	2026-10-10 10:25:56.534338+05:30
748	\N	doc-fad3ce481e4b	25	done	0	2026-10-10 10:25:56.577916+05:30	2026-10-10 10:25:56.62375+05:30
845	\N	doc-ff2f2247df35	3	done	0	2026-10-10 11:02:25.218479+05:30	2026-10-10 11:02:25.389836+05:30
749	\N	doc-0718297b71e4	25	done	0	2026-10-10 10:29:58.684342+05:30	2026-10-10 10:29:58.746236+05:30
750	\N	doc-de573a503f6d	25	done	0	2026-10-10 10:29:58.79611+05:30	2026-10-10 10:29:58.840729+05:30
853	\N	doc-50690e9459bb	6	done	0	2026-10-10 11:02:32.902408+05:30	2026-10-10 11:02:32.923614+05:30
751	\N	doc-03b90406eca2	25	done	0	2026-10-10 10:29:58.876573+05:30	2026-10-10 10:29:58.917545+05:30
752	\N	doc-0a51cdb40625	25	done	0	2026-10-10 10:29:58.964851+05:30	2026-10-10 10:29:58.990197+05:30
858	\N	doc-6c4fc0bf754c	9	done	0	2026-10-10 11:02:34.569703+05:30	2026-10-10 11:02:34.595176+05:30
753	\N	doc-9a4395663625	26	done	0	2026-10-10 10:29:59.041209+05:30	2026-10-10 10:29:59.074223+05:30
862	\N	doc-6c4fc0bf754c	11	done	0	2026-10-10 11:02:37.783704+05:30	2026-10-10 11:02:37.809791+05:30
754	\N	doc-becad9a82359	25	done	0	2026-10-10 10:29:59.123551+05:30	2026-10-10 10:29:59.163198+05:30
755	\N	doc-b02ac5215dad	25	done	0	2026-10-10 10:29:59.210132+05:30	2026-10-10 10:29:59.225133+05:30
863	\N	doc-a8180f3bb43d	6	done	0	2026-10-10 11:02:38.070338+05:30	2026-10-10 11:02:38.124711+05:30
756	\N	doc-37cea547ae24	25	done	0	2026-10-10 10:29:59.242749+05:30	2026-10-10 10:29:59.289246+05:30
757	\N	doc-5e4f6cd7d179	25	done	0	2026-10-10 10:29:59.339795+05:30	2026-10-10 10:29:59.379778+05:30
758	\N	doc-a453aa814971	25	done	0	2026-10-10 10:29:59.427239+05:30	2026-10-10 10:29:59.473654+05:30
759	\N	doc-e9cdba142890	25	done	0	2026-10-10 10:29:59.52508+05:30	2026-10-10 10:29:59.567986+05:30
760	\N	doc-bd628377481b	25	done	0	2026-10-10 10:29:59.613629+05:30	2026-10-10 10:29:59.657168+05:30
761	\N	doc-eb33be1c8687	25	done	0	2026-10-10 10:29:59.707795+05:30	2026-10-10 10:29:59.750209+05:30
762	\N	doc-8405e29cdc24	25	done	0	2026-10-10 10:29:59.79907+05:30	2026-10-10 10:29:59.841811+05:30
763	\N	doc-43c0cbab0d45	25	done	0	2026-10-10 10:29:59.874311+05:30	2026-10-10 10:29:59.921579+05:30
764	\N	doc-a2d6def96248	25	done	0	2026-10-10 10:29:59.961928+05:30	2026-10-10 10:30:00.012631+05:30
765	\N	doc-fad3ce481e4b	26	done	0	2026-10-10 10:30:00.058731+05:30	2026-10-10 10:30:00.108904+05:30
766	\N	doc-50690e9459bb	2	done	0	2026-10-10 10:33:50.103639+05:30	2026-10-10 10:33:50.149586+05:30
767	\N	doc-6c4fc0bf754c	2	done	0	2026-10-10 10:33:55.143349+05:30	2026-10-10 10:33:55.167246+05:30
768	\N	doc-a8180f3bb43d	2	done	0	2026-10-10 10:34:01.591847+05:30	2026-10-10 10:34:01.604759+05:30
769	\N	doc-24f027b6f4a7	2	done	0	2026-10-10 10:34:07.810381+05:30	2026-10-10 10:34:07.858609+05:30
904	\N	doc-ab5c26d1ac91	6	done	0	2026-10-10 11:03:03.144852+05:30	2026-10-10 11:03:03.194376+05:30
770	\N	doc-e8e98b8c83a3	2	done	0	2026-10-10 10:34:13.103324+05:30	2026-10-10 10:34:13.131453+05:30
771	\N	doc-75f8446029de	2	done	0	2026-10-10 10:34:19.699831+05:30	2026-10-10 10:34:19.765986+05:30
772	\N	doc-f86ce675b533	2	done	0	2026-10-10 10:34:26.27982+05:30	2026-10-10 10:34:26.309224+05:30
773	\N	doc-98940217eca3	2	done	0	2026-10-10 10:34:33.544447+05:30	2026-10-10 10:34:33.558469+05:30
774	\N	doc-ab5c26d1ac91	2	done	0	2026-10-10 10:34:41.973451+05:30	2026-10-10 10:34:41.993491+05:30
775	\N	doc-0718297b71e4	26	done	0	2026-10-10 10:34:44.73742+05:30	2026-10-10 10:34:44.800058+05:30
776	\N	doc-de573a503f6d	26	done	0	2026-10-10 10:34:44.839415+05:30	2026-10-10 10:34:44.877501+05:30
777	\N	doc-03b90406eca2	26	done	0	2026-10-10 10:34:44.917889+05:30	2026-10-10 10:34:44.976662+05:30
778	\N	doc-0a51cdb40625	26	done	0	2026-10-10 10:34:45.01018+05:30	2026-10-10 10:34:45.048397+05:30
779	\N	doc-9a4395663625	27	done	0	2026-10-10 10:34:45.082686+05:30	2026-10-10 10:34:45.127841+05:30
780	\N	doc-becad9a82359	26	done	0	2026-10-10 10:34:45.19904+05:30	2026-10-10 10:34:45.24755+05:30
781	\N	doc-b02ac5215dad	26	done	0	2026-10-10 10:34:45.28972+05:30	2026-10-10 10:34:45.316509+05:30
782	\N	doc-37cea547ae24	26	done	0	2026-10-10 10:34:45.369363+05:30	2026-10-10 10:34:45.412617+05:30
783	\N	doc-5e4f6cd7d179	26	done	0	2026-10-10 10:34:45.452146+05:30	2026-10-10 10:34:45.500486+05:30
784	\N	doc-a453aa814971	26	done	0	2026-10-10 10:34:45.534661+05:30	2026-10-10 10:34:45.579405+05:30
785	\N	doc-e9cdba142890	26	done	0	2026-10-10 10:34:45.628594+05:30	2026-10-10 10:34:45.688841+05:30
786	\N	doc-bd628377481b	26	done	0	2026-10-10 10:34:45.734775+05:30	2026-10-10 10:34:45.783232+05:30
787	\N	doc-eb33be1c8687	26	done	0	2026-10-10 10:34:45.862664+05:30	2026-10-10 10:34:45.90524+05:30
788	\N	doc-8405e29cdc24	26	done	0	2026-10-10 10:34:45.941332+05:30	2026-10-10 10:34:45.959669+05:30
789	\N	doc-43c0cbab0d45	26	done	0	2026-10-10 10:34:46.02564+05:30	2026-10-10 10:34:46.079871+05:30
790	\N	doc-a2d6def96248	26	done	0	2026-10-10 10:34:46.146456+05:30	2026-10-10 10:34:46.20121+05:30
791	\N	doc-fad3ce481e4b	27	done	0	2026-10-10 10:34:46.252274+05:30	2026-10-10 10:34:46.293462+05:30
792	\N	doc-becad9a82359	27	done	0	2026-10-10 10:34:46.362214+05:30	2026-10-10 10:34:46.404981+05:30
793	\N	doc-a2d6def96248	27	done	0	2026-10-10 10:34:46.458869+05:30	2026-10-10 10:34:46.49761+05:30
794	\N	doc-9a4395663625	28	done	0	2026-10-10 10:34:46.565847+05:30	2026-10-10 10:34:46.622492+05:30
795	\N	doc-37cea547ae24	27	done	0	2026-10-10 10:34:46.684583+05:30	2026-10-10 10:34:46.727651+05:30
815	\N	doc-a8180f3bb43d	3	done	0	2026-10-10 10:35:57.274415+05:30	2026-10-10 10:35:57.329953+05:30
818	\N	doc-75f8446029de	3	done	0	2026-10-10 10:36:07.622+05:30	2026-10-10 10:36:07.643513+05:30
821	\N	doc-ab5c26d1ac91	3	done	0	2026-10-10 10:36:17.773317+05:30	2026-10-10 10:36:17.830542+05:30
824	\N	doc-cf0975b45d02	3	done	0	2026-10-10 10:36:27.838619+05:30	2026-10-10 10:36:27.875361+05:30
827	\N	doc-f5e24b39a009	3	done	0	2026-10-10 10:36:37.734139+05:30	2026-10-10 10:36:37.77277+05:30
831	\N	doc-a8180f3bb43d	4	done	0	2026-10-10 11:02:04.398453+05:30	2026-10-10 11:02:04.423561+05:30
834	\N	doc-6c4fc0bf754c	5	done	0	2026-10-10 11:02:08.660861+05:30	2026-10-10 11:02:08.707494+05:30
838	\N	doc-24f027b6f4a7	5	done	0	2026-10-10 11:02:16.234667+05:30	2026-10-10 11:02:16.601779+05:30
839	\N	doc-f86ce675b533	4	done	0	2026-10-10 11:02:19.279258+05:30	2026-10-10 11:02:19.307234+05:30
842	\N	doc-75f8446029de	5	done	0	2026-10-10 11:02:24.706023+05:30	2026-10-10 11:02:24.757355+05:30
943	\N	doc-f5e24b39a009	8	done	0	2026-10-10 11:03:29.778933+05:30	2026-10-10 11:03:29.821949+05:30
844	\N	doc-ff2f2247df35	2	done	0	2026-10-10 11:02:25.206968+05:30	2026-10-10 11:02:25.337354+05:30
846	\N	doc-ff2f2247df35	4	done	0	2026-10-10 11:02:25.274226+05:30	2026-10-10 11:02:25.438946+05:30
945	\N	doc-95f9bf76e643	10	done	0	2026-10-10 11:03:32.045726+05:30	2026-10-10 11:03:32.067691+05:30
847	\N	doc-ff2f2247df35	4	done	0	2026-10-10 11:02:25.285395+05:30	2026-10-10 11:02:25.470474+05:30
849	\N	doc-ab5c26d1ac91	4	done	0	2026-10-10 11:02:27.669156+05:30	2026-10-10 11:02:27.692098+05:30
854	\N	doc-50690e9459bb	7	done	0	2026-10-10 11:02:33.701412+05:30	2026-10-10 11:02:33.74429+05:30
857	\N	doc-6c4fc0bf754c	8	done	0	2026-10-10 11:02:34.372294+05:30	2026-10-10 11:02:34.406867+05:30
865	\N	doc-a8180f3bb43d	8	done	0	2026-10-10 11:02:38.31844+05:30	2026-10-10 11:02:38.350569+05:30
866	\N	doc-a8180f3bb43d	9	done	0	2026-10-10 11:02:38.379277+05:30	2026-10-10 11:02:38.405312+05:30
870	\N	doc-a8180f3bb43d	11	done	0	2026-10-10 11:02:41.494913+05:30	2026-10-10 11:02:41.543911+05:30
871	\N	doc-24f027b6f4a7	6	done	0	2026-10-10 11:02:42.174247+05:30	2026-10-10 11:02:42.199362+05:30
873	\N	doc-24f027b6f4a7	8	done	0	2026-10-10 11:02:42.540764+05:30	2026-10-10 11:02:42.561397+05:30
874	\N	doc-24f027b6f4a7	9	done	0	2026-10-10 11:02:42.679546+05:30	2026-10-10 11:02:42.701637+05:30
878	\N	doc-24f027b6f4a7	11	done	0	2026-10-10 11:02:45.412227+05:30	2026-10-10 11:02:45.4329+05:30
879	\N	doc-e8e98b8c83a3	6	done	0	2026-10-10 11:02:46.161554+05:30	2026-10-10 11:02:46.199926+05:30
881	\N	doc-e8e98b8c83a3	8	done	0	2026-10-10 11:02:46.607124+05:30	2026-10-10 11:02:46.628687+05:30
882	\N	doc-e8e98b8c83a3	9	done	0	2026-10-10 11:02:46.733774+05:30	2026-10-10 11:02:46.758383+05:30
886	\N	doc-e8e98b8c83a3	11	done	0	2026-10-10 11:02:49.457773+05:30	2026-10-10 11:02:49.482776+05:30
887	\N	doc-75f8446029de	6	done	0	2026-10-10 11:02:50.070163+05:30	2026-10-10 11:02:50.093362+05:30
889	\N	doc-75f8446029de	8	done	0	2026-10-10 11:02:50.620764+05:30	2026-10-10 11:02:50.667905+05:30
890	\N	doc-75f8446029de	9	done	0	2026-10-10 11:02:50.811803+05:30	2026-10-10 11:02:50.834117+05:30
898	\N	doc-f86ce675b533	9	done	0	2026-10-10 11:02:54.957601+05:30	2026-10-10 11:02:54.987206+05:30
900	\N	doc-95f9bf76e643	5	done	0	2026-10-10 11:02:55.986316+05:30	2026-10-10 11:02:56.054139+05:30
903	\N	doc-98940217eca3	6	done	0	2026-10-10 11:03:03.114421+05:30	2026-10-10 11:03:03.140454+05:30
907	\N	doc-98940217eca3	9	done	0	2026-10-10 11:03:04.360649+05:30	2026-10-10 11:03:04.385633+05:30
912	\N	doc-ab5c26d1ac91	9	done	0	2026-10-10 11:03:07.85109+05:30	2026-10-10 11:03:07.906826+05:30
914	\N	doc-ab5c26d1ac91	11	done	0	2026-10-10 11:03:08.542486+05:30	2026-10-10 11:03:08.572464+05:30
918	\N	doc-3d054e40aba7	9	done	0	2026-10-10 11:03:11.740713+05:30	2026-10-10 11:03:11.795295+05:30
920	\N	doc-3d054e40aba7	11	done	0	2026-10-10 11:03:12.098101+05:30	2026-10-10 11:03:12.121764+05:30
924	\N	doc-d6402dc16e20	10	done	0	2026-10-10 11:03:15.96319+05:30	2026-10-10 11:03:16.005851+05:30
926	\N	doc-d6402dc16e20	12	done	0	2026-10-10 11:03:16.004516+05:30	2026-10-10 11:03:16.065441+05:30
932	\N	doc-cf0975b45d02	11	done	0	2026-10-10 11:03:20.480924+05:30	2026-10-10 11:03:20.501313+05:30
936	\N	doc-95f9bf76e643	7	done	0	2026-10-10 11:03:26.075468+05:30	2026-10-10 11:03:26.152013+05:30
942	\N	doc-f5e24b39a009	7	done	0	2026-10-10 11:03:29.348659+05:30	2026-10-10 11:03:29.400247+05:30
946	\N	doc-95f9bf76e643	11	done	0	2026-10-10 11:03:32.092173+05:30	2026-10-10 11:03:32.137735+05:30
949	\N	doc-f5e24b39a009	11	done	0	2026-10-10 11:03:35.843227+05:30	2026-10-10 11:03:35.870208+05:30
950	\N	doc-ff2f2247df35	5	done	0	2026-10-10 11:08:05.923642+05:30	2026-10-10 11:08:05.983309+05:30
951	\N	doc-50690e9459bb	8	done	0	2026-10-10 11:08:05.998388+05:30	2026-10-10 11:08:06.076456+05:30
954	\N	doc-f5e24b39a009	12	done	0	2026-10-10 11:23:42.813482+05:30	2026-10-10 11:23:42.91541+05:30
816	\N	doc-24f027b6f4a7	3	done	0	2026-10-10 10:36:01.316581+05:30	2026-10-10 10:36:01.359424+05:30
796	\N	doc-03b90406eca2	27	done	0	2026-10-10 10:34:46.768365+05:30	2026-10-10 10:34:46.82603+05:30
819	\N	doc-f86ce675b533	3	done	0	2026-10-10 10:36:10.670696+05:30	2026-10-10 10:36:10.690643+05:30
797	\N	doc-5e4f6cd7d179	27	done	0	2026-10-10 10:34:46.87791+05:30	2026-10-10 10:34:46.929761+05:30
822	\N	doc-3d054e40aba7	3	done	0	2026-10-10 10:36:21.16518+05:30	2026-10-10 10:36:21.191224+05:30
798	\N	doc-43c0cbab0d45	27	done	0	2026-10-10 10:34:46.983736+05:30	2026-10-10 10:34:47.057959+05:30
825	\N	doc-4f328576121e	3	done	0	2026-10-10 10:36:31.316748+05:30	2026-10-10 10:36:31.365001+05:30
799	\N	doc-eb33be1c8687	27	done	0	2026-10-10 10:34:47.101826+05:30	2026-10-10 10:34:47.144182+05:30
800	\N	doc-0718297b71e4	27	done	0	2026-10-10 10:34:47.198758+05:30	2026-10-10 10:34:47.244351+05:30
832	\N	doc-50690e9459bb	5	done	0	2026-10-10 11:02:05.221991+05:30	2026-10-10 11:02:05.249999+05:30
801	\N	doc-0a51cdb40625	27	done	0	2026-10-10 10:34:47.285905+05:30	2026-10-10 10:34:47.33267+05:30
802	\N	doc-fad3ce481e4b	28	done	0	2026-10-10 10:34:47.380701+05:30	2026-10-10 10:34:47.429801+05:30
836	\N	doc-a8180f3bb43d	5	done	0	2026-10-10 11:02:12.488433+05:30	2026-10-10 11:02:12.532391+05:30
803	\N	doc-8405e29cdc24	27	done	0	2026-10-10 10:34:47.495169+05:30	2026-10-10 10:34:47.537731+05:30
804	\N	doc-b02ac5215dad	27	done	0	2026-10-10 10:34:47.579905+05:30	2026-10-10 10:34:47.629484+05:30
840	\N	doc-e8e98b8c83a3	5	done	0	2026-10-10 11:02:19.978208+05:30	2026-10-10 11:02:20.032467+05:30
805	\N	doc-e9cdba142890	27	done	0	2026-10-10 10:34:47.683027+05:30	2026-10-10 10:34:47.731065+05:30
806	\N	doc-a453aa814971	27	done	0	2026-10-10 10:34:47.789734+05:30	2026-10-10 10:34:47.813152+05:30
848	\N	doc-ff2f2247df35	4	done	0	2026-10-10 11:02:25.287395+05:30	2026-10-10 11:02:25.491637+05:30
850	\N	doc-f86ce675b533	5	done	0	2026-10-10 11:02:28.649151+05:30	2026-10-10 11:02:28.692586+05:30
851	\N	doc-3d054e40aba7	4	done	0	2026-10-10 11:02:31.158172+05:30	2026-10-10 11:02:31.205086+05:30
855	\N	doc-6c4fc0bf754c	6	done	0	2026-10-10 11:02:34.015227+05:30	2026-10-10 11:02:34.034142+05:30
856	\N	doc-6c4fc0bf754c	7	done	0	2026-10-10 11:02:34.291293+05:30	2026-10-10 11:02:34.314282+05:30
860	\N	doc-ab5c26d1ac91	5	done	0	2026-10-10 11:02:36.17708+05:30	2026-10-10 11:02:36.201184+05:30
864	\N	doc-a8180f3bb43d	7	done	0	2026-10-10 11:02:38.232464+05:30	2026-10-10 11:02:38.276759+05:30
868	\N	doc-3d054e40aba7	5	done	0	2026-10-10 11:02:39.9907+05:30	2026-10-10 11:02:40.015153+05:30
872	\N	doc-24f027b6f4a7	7	done	0	2026-10-10 11:02:42.407952+05:30	2026-10-10 11:02:42.448076+05:30
877	\N	doc-d6402dc16e20	6	done	0	2026-10-10 11:02:44.234451+05:30	2026-10-10 11:02:44.273301+05:30
880	\N	doc-e8e98b8c83a3	7	done	0	2026-10-10 11:02:46.371102+05:30	2026-10-10 11:02:46.41749+05:30
884	\N	doc-cf0975b45d02	5	done	0	2026-10-10 11:02:48.17943+05:30	2026-10-10 11:02:48.228198+05:30
888	\N	doc-75f8446029de	7	done	0	2026-10-10 11:02:50.351036+05:30	2026-10-10 11:02:50.371952+05:30
892	\N	doc-4f328576121e	5	done	0	2026-10-10 11:02:51.988501+05:30	2026-10-10 11:02:52.008547+05:30
896	\N	doc-f86ce675b533	7	done	0	2026-10-10 11:02:54.255101+05:30	2026-10-10 11:02:54.299793+05:30
897	\N	doc-f86ce675b533	8	done	0	2026-10-10 11:02:54.807242+05:30	2026-10-10 11:02:54.838636+05:30
899	\N	doc-f86ce675b533	10	done	0	2026-10-10 11:02:55.985293+05:30	2026-10-10 11:02:56.038214+05:30
906	\N	doc-98940217eca3	8	done	0	2026-10-10 11:03:03.830198+05:30	2026-10-10 11:03:03.871961+05:30
908	\N	doc-98940217eca3	10	done	0	2026-10-10 11:03:04.755939+05:30	2026-10-10 11:03:04.775621+05:30
910	\N	doc-ab5c26d1ac91	7	done	0	2026-10-10 11:03:06.922297+05:30	2026-10-10 11:03:06.95911+05:30
915	\N	doc-3d054e40aba7	7	done	0	2026-10-10 11:03:10.622636+05:30	2026-10-10 11:03:10.704906+05:30
922	\N	doc-cf0975b45d02	6	done	0	2026-10-10 11:03:14.681137+05:30	2026-10-10 11:03:14.710926+05:30
928	\N	doc-4f328576121e	6	done	0	2026-10-10 11:03:18.725844+05:30	2026-10-10 11:03:18.76756+05:30
931	\N	doc-cf0975b45d02	10	done	0	2026-10-10 11:03:20.293611+05:30	2026-10-10 11:03:20.357114+05:30
935	\N	doc-95f9bf76e643	6	done	0	2026-10-10 11:03:22.855011+05:30	2026-10-10 11:03:22.909408+05:30
940	\N	doc-4f328576121e	10	done	0	2026-10-10 11:03:28.404772+05:30	2026-10-10 11:03:28.440195+05:30
947	\N	doc-f5e24b39a009	9	done	0	2026-10-10 11:03:35.064297+05:30	2026-10-10 11:03:35.123107+05:30
952	\N	doc-4f328576121e	12	done	0	2026-10-10 11:08:06.092551+05:30	2026-10-10 11:08:06.148296+05:30
807	\N	doc-3d054e40aba7	2	done	0	2026-10-10 10:34:47.859657+05:30	2026-10-10 10:34:47.881207+05:30
828	\N	doc-d6402dc16e20	4	done	0	2026-10-10 10:36:48.390205+05:30	2026-10-10 10:36:48.434262+05:30
808	\N	doc-d6402dc16e20	2	done	0	2026-10-10 10:34:54.233399+05:30	2026-10-10 10:34:54.282584+05:30
809	\N	doc-cf0975b45d02	2	done	0	2026-10-10 10:35:01.875599+05:30	2026-10-10 10:35:01.924879+05:30
833	\N	doc-24f027b6f4a7	4	done	0	2026-10-10 11:02:08.147457+05:30	2026-10-10 11:02:08.167971+05:30
810	\N	doc-4f328576121e	2	done	0	2026-10-10 10:35:08.956821+05:30	2026-10-10 10:35:09.010966+05:30
835	\N	doc-e8e98b8c83a3	4	done	0	2026-10-10 11:02:12.399037+05:30	2026-10-10 11:02:12.447571+05:30
811	\N	doc-95f9bf76e643	2	done	0	2026-10-10 10:35:19.21013+05:30	2026-10-10 10:35:19.244213+05:30
812	\N	doc-f5e24b39a009	2	done	0	2026-10-10 10:35:26.502584+05:30	2026-10-10 10:35:26.569058+05:30
939	\N	doc-4f328576121e	9	done	0	2026-10-10 11:03:28.015915+05:30	2026-10-10 11:03:28.06342+05:30
843	\N	doc-ff2f2247df35	2	done	0	2026-10-10 11:02:25.201695+05:30	2026-10-10 11:02:25.282878+05:30
859	\N	doc-d6402dc16e20	5	done	0	2026-10-10 11:02:35.270377+05:30	2026-10-10 11:02:35.322171+05:30
861	\N	doc-6c4fc0bf754c	10	done	0	2026-10-10 11:02:36.684983+05:30	2026-10-10 11:02:36.72605+05:30
867	\N	doc-cf0975b45d02	4	done	0	2026-10-10 11:02:39.483724+05:30	2026-10-10 11:02:39.528203+05:30
869	\N	doc-a8180f3bb43d	10	done	0	2026-10-10 11:02:40.369409+05:30	2026-10-10 11:02:40.393979+05:30
875	\N	doc-4f328576121e	4	done	0	2026-10-10 11:02:43.787672+05:30	2026-10-10 11:02:43.814312+05:30
876	\N	doc-24f027b6f4a7	10	done	0	2026-10-10 11:02:44.205887+05:30	2026-10-10 11:02:44.227107+05:30
883	\N	doc-95f9bf76e643	4	done	0	2026-10-10 11:02:47.694725+05:30	2026-10-10 11:02:47.735005+05:30
885	\N	doc-e8e98b8c83a3	10	done	0	2026-10-10 11:02:48.325851+05:30	2026-10-10 11:02:48.38293+05:30
891	\N	doc-f5e24b39a009	4	done	0	2026-10-10 11:02:51.64356+05:30	2026-10-10 11:02:51.668016+05:30
893	\N	doc-75f8446029de	10	done	0	2026-10-10 11:02:52.067634+05:30	2026-10-10 11:02:52.114039+05:30
894	\N	doc-75f8446029de	11	done	0	2026-10-10 11:02:53.178818+05:30	2026-10-10 11:02:53.2381+05:30
895	\N	doc-f86ce675b533	6	done	0	2026-10-10 11:02:54.14624+05:30	2026-10-10 11:02:54.187806+05:30
901	\N	doc-f86ce675b533	11	done	0	2026-10-10 11:02:56.846249+05:30	2026-10-10 11:02:56.873162+05:30
902	\N	doc-f5e24b39a009	5	done	0	2026-10-10 11:03:00.543373+05:30	2026-10-10 11:03:00.570094+05:30
905	\N	doc-98940217eca3	7	done	0	2026-10-10 11:03:03.729215+05:30	2026-10-10 11:03:03.779772+05:30
909	\N	doc-3d054e40aba7	6	done	0	2026-10-10 11:03:06.909261+05:30	2026-10-10 11:03:06.942496+05:30
911	\N	doc-ab5c26d1ac91	8	done	0	2026-10-10 11:03:07.735718+05:30	2026-10-10 11:03:07.764974+05:30
913	\N	doc-ab5c26d1ac91	10	done	0	2026-10-10 11:03:08.252762+05:30	2026-10-10 11:03:08.301694+05:30
916	\N	doc-d6402dc16e20	7	done	0	2026-10-10 11:03:10.682541+05:30	2026-10-10 11:03:10.739259+05:30
917	\N	doc-3d054e40aba7	8	done	0	2026-10-10 11:03:11.433848+05:30	2026-10-10 11:03:11.484441+05:30
919	\N	doc-3d054e40aba7	10	done	0	2026-10-10 11:03:11.880324+05:30	2026-10-10 11:03:11.901882+05:30
921	\N	doc-d6402dc16e20	8	done	0	2026-10-10 11:03:14.59717+05:30	2026-10-10 11:03:14.619979+05:30
923	\N	doc-d6402dc16e20	9	done	0	2026-10-10 11:03:15.192101+05:30	2026-10-10 11:03:15.215135+05:30
925	\N	doc-d6402dc16e20	11	done	0	2026-10-10 11:03:15.981582+05:30	2026-10-10 11:03:16.0496+05:30
927	\N	doc-cf0975b45d02	7	done	0	2026-10-10 11:03:18.65099+05:30	2026-10-10 11:03:18.696127+05:30
929	\N	doc-cf0975b45d02	8	done	0	2026-10-10 11:03:18.916422+05:30	2026-10-10 11:03:18.935458+05:30
930	\N	doc-cf0975b45d02	9	done	0	2026-10-10 11:03:20.238697+05:30	2026-10-10 11:03:20.275669+05:30
933	\N	doc-4f328576121e	7	done	0	2026-10-10 11:03:22.397099+05:30	2026-10-10 11:03:22.424733+05:30
934	\N	doc-4f328576121e	8	done	0	2026-10-10 11:03:22.756836+05:30	2026-10-10 11:03:22.782984+05:30
937	\N	doc-95f9bf76e643	8	done	0	2026-10-10 11:03:26.53092+05:30	2026-10-10 11:03:26.581565+05:30
938	\N	doc-f5e24b39a009	6	done	0	2026-10-10 11:03:26.727084+05:30	2026-10-10 11:03:26.75301+05:30
941	\N	doc-4f328576121e	11	done	0	2026-10-10 11:03:28.418346+05:30	2026-10-10 11:03:28.504817+05:30
944	\N	doc-95f9bf76e643	9	done	0	2026-10-10 11:03:31.565814+05:30	2026-10-10 11:03:31.615068+05:30
948	\N	doc-f5e24b39a009	10	done	0	2026-10-10 11:03:35.647038+05:30	2026-10-10 11:03:35.691505+05:30
953	\N	doc-98940217eca3	11	done	0	2026-10-10 11:08:06.156728+05:30	2026-10-10 11:08:06.210087+05:30
\.


--
-- Data for Name: audit_logs_default; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.audit_logs_default (id, tenant_id, occurred_at, actor_type, actor_user_id, action, resource_type, resource_id, outcome, request_id, ip, user_agent, details, prev_hash, row_hash, severity, user_id, detail, created_at) FROM stdin;
ad2b76fd-e574-4e2a-baf2-640219742397	\N	2026-10-07 18:41:10.3018+05:30	\N	\N	ask	knowledge_base	3	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	How many days of PTO do full-time employees accrue annually?	2026-10-07 18:41:10.3018+05:30
9c06a3ac-b41b-4f20-8dbc-e9de5b348018	\N	2026-10-07 19:00:14.210703+05:30	\N	\N	system_initialized	system	\N	\N	\N	\N	\N	{}	\N	\N	INFO	82b1aa8b-2641-4866-8792-c5f40e8c468d	System initialized for finTech with root administrator test@example.com	2026-10-07 19:00:14.210703+05:30
6a5ad0ad-5e18-4e78-aa31-6647e645bcbc	\N	2026-10-07 19:00:24.156433+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-07 19:00:24.156433+05:30
fd0b0197-4d8f-461b-8073-7b469598c916	\N	2026-10-07 19:00:34.460086+05:30	\N	\N	login_failed	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	\N	Failed login attempt for email admin@example.com	2026-10-07 19:00:34.460086+05:30
6b2ee944-cd36-422b-9f12-f5be0b4be167	\N	2026-10-07 19:00:40.137226+05:30	\N	\N	password_reset_request	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	Reset request for admin@example.com	2026-10-07 19:00:40.137226+05:30
ca8e9004-8568-45d1-93b2-a43a38a23a82	\N	2026-10-07 19:00:50.96835+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-07 19:00:50.96835+05:30
a52b487a-4cde-4938-9029-4240dc0fdd64	\N	2026-10-07 19:00:55.445614+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	8fdffb04-e6c2-4c1c-8813-1e9a0767e82e	User hr@example.com logged in successfully	2026-10-07 19:00:55.445614+05:30
984931f9-43d8-4b35-a496-57077bef9f66	\N	2026-10-07 19:01:13.093708+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	82b1aa8b-2641-4866-8792-c5f40e8c468d	User test@example.com logged in successfully	2026-10-07 19:01:13.093708+05:30
404332fc-80f7-478b-9da7-7da83ae8536f	\N	2026-10-07 19:01:24.582312+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	5b04509c-2d7f-4a1f-8a04-203a1f244904	User manager@example.com logged in successfully	2026-10-07 19:01:24.582312+05:30
47b4cb43-0e3e-4bbb-ba5e-72c98665deff	\N	2026-10-07 19:03:21.669515+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-07 19:03:21.669515+05:30
cceae1dc-9614-42de-9f8e-274b6af5c36e	\N	2026-10-07 19:04:34.004182+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-07 19:04:34.004182+05:30
8de6c713-e2af-4e2a-9620-62183a2181f2	\N	2026-10-07 19:05:54.89754+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-07 19:05:54.89754+05:30
89e207d5-cea7-4096-8fd0-b5bbe0c0013c	\N	2026-10-07 19:06:08.635639+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	5 documents visible	2026-10-07 19:06:08.635639+05:30
b7ce2fd4-b36e-4766-b71f-514d355f12cf	\N	2026-10-07 19:06:08.66404+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	5 documents visible	2026-10-07 19:06:08.66404+05:30
55968b37-91d1-4602-80d4-e25cbf117bbb	\N	2026-10-07 19:06:13.531583+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	5 documents visible	2026-10-07 19:06:13.531583+05:30
3c4d9a84-732e-45f9-a71e-974e38652c70	\N	2026-10-07 19:06:13.554256+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	5 documents visible	2026-10-07 19:06:13.554256+05:30
9143ca86-f062-42a4-b4ea-50c56360cf26	\N	2026-10-07 19:06:25.371093+05:30	\N	\N	delete	document	46e07ba0-2f08-401f-b4f9-b7917d937e12	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	\N	2026-10-07 19:06:25.371093+05:30
1823ec50-b142-4b91-8148-1a855b23e6bd	\N	2026-10-07 19:06:29.187711+05:30	\N	\N	delete	document	doc-90522638f048	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	\N	2026-10-07 19:06:29.187711+05:30
a92b5eec-72cb-4716-bdff-54ff63235e32	\N	2026-10-07 19:06:31.570859+05:30	\N	\N	delete	document	b1fb4ea1-55e8-4d2c-b53c-93d8bb4e1500	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	\N	2026-10-07 19:06:31.570859+05:30
8b7e038e-6ae4-4c6a-b9fc-9feda192d254	\N	2026-10-07 19:06:54.059884+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	3 documents visible	2026-10-07 19:06:54.059884+05:30
d9dd47cb-120a-48c9-9171-2d9d5ba1df84	\N	2026-10-07 19:06:54.079159+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	3 documents visible	2026-10-07 19:06:54.079159+05:30
52433935-1d5f-41da-af66-daf5238cc974	\N	2026-10-07 19:07:18.673998+05:30	\N	\N	ingest	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	3 local files processed	2026-10-07 19:07:18.673998+05:30
f897403e-e111-431a-9d36-05d7b2027f38	\N	2026-10-07 19:08:34.926906+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	3 documents visible	2026-10-07 19:08:34.926906+05:30
583ba87e-12fc-48bc-b9cd-1bd1193c62d6	\N	2026-10-07 19:08:34.950214+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	3 documents visible	2026-10-07 19:08:34.950214+05:30
0730c466-6d13-4bb3-9984-ed526c692a3f	\N	2026-10-07 19:09:40.71886+05:30	\N	\N	ingest	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 local files processed	2026-10-07 19:09:40.71886+05:30
21797d14-2442-42ba-a6c8-17945b5d0a32	\N	2026-10-07 19:10:44.437981+05:30	\N	\N	update_access	document	doc-f34d3b0e0c4d	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	["hr", "manager"]	2026-10-07 19:10:44.437981+05:30
3477a23d-5f7e-43d5-a6b8-7b96f79679be	\N	2026-10-07 19:11:04.788078+05:30	\N	\N	update_access	document	doc-27eadc26a7a2	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	["admin", "hr"]	2026-10-07 19:11:04.788078+05:30
afb720fa-1f65-473f-9d63-408160226368	\N	2026-10-07 19:11:30.161993+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	18 documents visible	2026-10-07 19:11:30.161993+05:30
e0dd1917-5c36-4cbd-b213-53df32e6be54	\N	2026-10-07 19:11:30.227563+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	18 documents visible	2026-10-07 19:11:30.227563+05:30
3d3f819a-c657-400f-b4e9-7a2648b90d89	\N	2026-10-07 19:12:46.146245+05:30	\N	\N	ask	knowledge_base	4	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	what is work from home policy	2026-10-07 19:12:46.146245+05:30
09aa399e-816f-4789-9881-06c16ec58a4d	\N	2026-10-07 19:14:43.534326+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	18 documents visible	2026-10-07 19:14:43.534326+05:30
1078706e-e7c8-47a5-9bd2-b61c940c599b	\N	2026-10-07 19:14:43.602502+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	18 documents visible	2026-10-07 19:14:43.602502+05:30
22e9d5be-2ff9-473d-b67b-ea56c5f9b831	\N	2026-10-07 19:14:55.182166+05:30	\N	\N	ask	knowledge_base	5	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	Who needs to approve international travel for an L5 employee?	2026-10-07 19:14:55.182166+05:30
5e3ed7ea-0c53-4854-aaca-7db2cc679f5a	\N	2026-10-07 19:16:18.527692+05:30	\N	\N	ask	knowledge_base	6	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	How many working days in advance must international travel be approved?	2026-10-07 19:16:18.527692+05:30
a2c0ff10-aa3d-4e15-a278-2c37e76dd083	\N	2026-10-07 20:41:19.000416+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	8fdffb04-e6c2-4c1c-8813-1e9a0767e82e	User hr@example.com logged in successfully	2026-10-07 20:41:19.000416+05:30
d8531af1-8115-4f1b-b51f-97ba3ee5e419	\N	2026-10-07 20:56:49.957879+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	8fdffb04-e6c2-4c1c-8813-1e9a0767e82e	18 documents visible	2026-10-07 20:56:49.957879+05:30
5ac4d943-4fd6-4b2e-9fe9-46c20a4852e2	\N	2026-10-07 20:56:50.294483+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	8fdffb04-e6c2-4c1c-8813-1e9a0767e82e	18 documents visible	2026-10-07 20:56:50.294483+05:30
332d6e67-2397-4b6e-be99-ae6b9bfac289	\N	2026-10-07 20:57:01.200161+05:30	\N	\N	update_access	document	doc-f4de4672f657	\N	\N	\N	\N	{}	\N	\N	INFO	8fdffb04-e6c2-4c1c-8813-1e9a0767e82e	["admin", "hr"]	2026-10-07 20:57:01.200161+05:30
b8578b77-49e8-495d-8747-dcbc7a34cccf	\N	2026-10-07 20:57:23.254954+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-07 20:57:23.254954+05:30
a7108706-64b6-4dfb-b60e-e87aa6e2a30b	\N	2026-10-07 20:57:23.74135+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	18 documents visible	2026-10-07 20:57:23.74135+05:30
3fa4c470-ebdd-4333-8409-6cdacc555dbe	\N	2026-10-07 20:57:23.79299+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	18 documents visible	2026-10-07 20:57:23.79299+05:30
b9137ce9-576d-413f-80aa-943e03e003ef	\N	2026-10-07 20:57:06.046814+05:30	\N	\N	summarize	document	doc-f4de4672f657	\N	\N	\N	\N	{}	\N	\N	INFO	8fdffb04-e6c2-4c1c-8813-1e9a0767e82e	\N	2026-10-07 20:57:06.046814+05:30
3e9fd398-8d2f-4ebd-9adb-276850e4dc24	\N	2026-10-08 20:19:49.491144+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-08 20:19:49.491144+05:30
94c3ece7-888a-41a5-868e-4521269bcab6	\N	2026-10-08 20:19:52.25288+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	18 documents visible	2026-10-08 20:19:52.25288+05:30
d8cd547c-58b9-4442-a4a7-129394b7cacc	\N	2026-10-08 20:19:52.313364+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	18 documents visible	2026-10-08 20:19:52.313364+05:30
9e09f9f6-fe19-4504-8fc1-10cd6c447830	\N	2026-10-08 20:20:27.267268+05:30	\N	\N	ask	knowledge_base	7	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	who needs to approve international travel for an L5 employee?	2026-10-08 20:20:27.267268+05:30
8cf2f14d-da8e-439c-852d-9b481d48a244	\N	2026-10-08 20:21:01.401638+05:30	\N	\N	ask	knowledge_base	8	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	How many working days in advance must international travel be approved?	2026-10-08 20:21:01.401638+05:30
16cec983-203a-4bdd-9c1a-4cbc3c5944e6	\N	2026-10-08 20:21:17.111638+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	18 documents visible	2026-10-08 20:21:17.111638+05:30
d0eefa86-1548-4558-b355-105dbf2f0e2d	\N	2026-10-08 20:21:17.188303+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	18 documents visible	2026-10-08 20:21:17.188303+05:30
93ebc899-e346-4f53-b292-10be329e53ea	\N	2026-10-08 20:37:10.315568+05:30	\N	\N	create_user	user	ad5a4022-ce1b-4ce0-8599-af48d160698d	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	Created user test1@example.com with role 'employee' (Rank Level 4)	2026-10-08 20:37:10.315568+05:30
d09e853b-6f71-4599-adbc-3ba107463a2a	\N	2026-10-08 20:37:38.078586+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	ad5a4022-ce1b-4ce0-8599-af48d160698d	User test1@example.com logged in successfully	2026-10-08 20:37:38.078586+05:30
6aacc987-37e7-49f7-a1ac-14f511904038	\N	2026-10-08 20:37:41.963173+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	ad5a4022-ce1b-4ce0-8599-af48d160698d	12 documents visible	2026-10-08 20:37:41.963173+05:30
0bef1b8e-aafc-43fd-892c-46610a4e3c22	\N	2026-10-08 20:37:42.137829+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	ad5a4022-ce1b-4ce0-8599-af48d160698d	12 documents visible	2026-10-08 20:37:42.137829+05:30
5e9d79e7-a7bf-4521-a3b7-88a66898a13e	\N	2026-10-08 20:37:43.967287+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	ad5a4022-ce1b-4ce0-8599-af48d160698d	12 documents visible	2026-10-08 20:37:43.967287+05:30
5a6e544b-ea9d-4223-9c26-40c1f400c29c	\N	2026-10-08 20:37:44.199059+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	ad5a4022-ce1b-4ce0-8599-af48d160698d	12 documents visible	2026-10-08 20:37:44.199059+05:30
ffd78422-0396-4e7b-951f-13152bac36c8	\N	2026-10-08 20:37:45.275963+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	ad5a4022-ce1b-4ce0-8599-af48d160698d	12 documents visible	2026-10-08 20:37:45.275963+05:30
8ee0e8ba-8c4e-40b3-9856-15f765fe5ff0	\N	2026-10-08 20:37:45.147201+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	ad5a4022-ce1b-4ce0-8599-af48d160698d	12 documents visible	2026-10-08 20:37:45.147201+05:30
0e48d408-e656-49fa-90a0-db0f3065e5df	\N	2026-10-08 21:38:10.077416+05:30	\N	\N	add_enterprise	enterprise	admin@acmecorp.com	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	Connected new enterprise 'Acme Global Corp' with Admin email 'admin@acmecorp.com'	2026-10-08 21:38:10.077416+05:30
1b3afea1-aa14-4558-9b6e-96ec831e1839	\N	2026-10-08 21:38:10.31357+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	User admin@acmecorp.com logged in successfully	2026-10-08 21:38:10.31357+05:30
72a2c09f-116f-42c2-8e06-3b33d9771bd9	\N	2026-10-08 21:38:10.529217+05:30	\N	\N	toggle_enterprise_status	enterprise	1	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	Set enterprise 'Acme Global Corp' (admin@acmecorp.com) status to Deactivated	2026-10-08 21:38:10.529217+05:30
4bd545ca-9170-40a8-a3f9-6840b7f43bdb	\N	2026-10-08 21:38:10.542365+05:30	\N	\N	login_blocked	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	Deactivated user admin@acmecorp.com attempted login	2026-10-08 21:38:10.542365+05:30
de388272-c7db-4894-822f-78fef3d6abed	\N	2026-10-08 21:38:10.749038+05:30	\N	\N	toggle_enterprise_status	enterprise	1	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	Set enterprise 'Acme Global Corp' (admin@acmecorp.com) status to Active	2026-10-08 21:38:10.749038+05:30
6f4a2f0a-c8d2-4814-b8d4-4853a282f231	\N	2026-10-08 22:06:09.221161+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-08 22:06:09.221161+05:30
3560dfd7-3262-4593-ac2d-68daae41b664	\N	2026-10-08 22:06:17.422575+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-08 22:06:17.422575+05:30
84a72c7f-39d8-4819-95a4-f273ff7feb94	\N	2026-10-08 22:06:17.480474+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-08 22:06:17.480474+05:30
b90b3257-232c-4c72-a20a-9079effe03fd	\N	2026-10-08 22:06:18.174717+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-08 22:06:18.174717+05:30
b2e9c728-1db6-4806-a5f6-dc2766954800	\N	2026-10-08 22:06:18.292195+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-08 22:06:18.292195+05:30
8347555e-3e70-4956-981f-b77590f73283	\N	2026-10-08 22:06:20.122907+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-08 22:06:20.122907+05:30
2cfc6fc9-8f87-4945-866f-65c70969298b	\N	2026-10-08 22:06:20.22216+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-08 22:06:20.22216+05:30
13ecbc21-4f67-4964-bfec-fcb5e85f2938	\N	2026-10-08 22:06:23.537201+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-08 22:06:23.537201+05:30
3c03705f-206a-4e59-9bb8-275770899885	\N	2026-10-08 22:06:23.689825+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-08 22:06:23.689825+05:30
f98cb403-dda5-4cc7-b436-a996d72addd9	\N	2026-10-08 22:09:24.34254+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-08 22:09:24.34254+05:30
ade1b3dc-0d5e-46a1-9957-267e357b0076	\N	2026-10-08 22:13:19.963919+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-08 22:13:19.963919+05:30
97765f34-df2d-4e29-9616-3c3ec1dd8f9b	\N	2026-10-08 22:13:30.902964+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	8fdffb04-e6c2-4c1c-8813-1e9a0767e82e	User hr@example.com logged in successfully	2026-10-08 22:13:30.902964+05:30
ce11c7d7-0ff5-4e81-8fa9-4a1a4722e27e	\N	2026-10-08 22:22:55.123044+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	User system@gmailexample.com logged in successfully	2026-10-08 22:22:55.123044+05:30
a17eca83-eed2-4871-91b2-0fd92a5fe96e	\N	2026-10-08 22:25:29.762806+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	User system@gmailexample.com logged in successfully	2026-10-08 22:25:29.762806+05:30
d2248bca-4851-4968-b956-85dbcf278d86	\N	2026-10-08 22:33:52.291871+05:30	\N	\N	add_enterprise	enterprise	admin@apex.com	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	Connected new enterprise 'Apex Tech' with Admin email 'admin@apex.com'	2026-10-08 22:33:52.291871+05:30
cad0fced-501a-4bd4-ae5f-0ecae283a6dd	\N	2026-10-08 22:34:34.674854+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-08 22:34:34.674854+05:30
1c07a441-b244-4263-b7db-daac352ffef7	\N	2026-10-08 22:34:44.744813+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	17 documents visible	2026-10-08 22:34:44.744813+05:30
7de08ad9-1d50-4659-afec-b493f7511c86	\N	2026-10-08 22:34:44.833219+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	17 documents visible	2026-10-08 22:34:44.833219+05:30
8121199a-1bb2-4770-b07c-408e69c45289	\N	2026-10-08 22:34:48.368585+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	17 documents visible	2026-10-08 22:34:48.368585+05:30
6d0406b2-a48f-4fef-a0e8-5d1453fb4cf3	\N	2026-10-08 22:34:48.416438+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	17 documents visible	2026-10-08 22:34:48.416438+05:30
ae7b3fec-b1fe-4782-b3cd-e930705112b7	\N	2026-10-09 09:47:55.051527+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	User system@gmailexample.com logged in successfully	2026-10-09 09:47:55.051527+05:30
3c8776c3-de41-438d-916a-1e44a49c6f62	a3424830-6d45-4ad8-a43b-a5fdf70d691d	2026-10-09 09:52:35.356796+05:30	\N	\N	add_enterprise	enterprise	admin@acmecorp.com	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	Connected enterprise 'Acme Corporation' (Tenant: a3424830-6d45-4ad8-a43b-a5fdf70d691d) with Admin 'admin@acmecorp.com'	2026-10-09 09:52:35.356796+05:30
30aaf126-1db1-4b41-95a0-39af5c9700c6	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-09 09:52:36.037715+05:30	\N	\N	add_enterprise	enterprise	admin@apex.com	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	Connected enterprise 'Apex Technologies' (Tenant: df672f52-b432-45f1-b1a6-4b4b78e23065) with Admin 'admin@apex.com'	2026-10-09 09:52:36.037715+05:30
f6df7d95-e512-4aff-924a-2a8df71e5d2d	\N	2026-10-09 09:58:41.859309+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	User system@gmailexample.com logged in successfully	2026-10-09 09:58:41.859309+05:30
c81432de-d656-48a0-be28-21e2ace36d29	69bb5e9f-858a-4cdc-a6f4-e05b1a80494b	2026-10-09 09:59:27.74813+05:30	\N	\N	add_enterprise	enterprise	cmp3@example.com	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	Connected enterprise 'cmp3' (Tenant: 69bb5e9f-858a-4cdc-a6f4-e05b1a80494b) with Admin 'cmp3@example.com'	2026-10-09 09:59:27.74813+05:30
ea4e2564-2af9-43ce-9ab6-3933aeb81f4c	\N	2026-10-09 09:59:53.562604+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	e4130151-2b46-40e5-b604-ed235045a782	User cmp3@example.com logged in successfully	2026-10-09 09:59:53.562604+05:30
a873f42b-d837-4752-b6bd-beca848edc58	\N	2026-10-09 10:00:00.493495+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	e4130151-2b46-40e5-b604-ed235045a782	0 documents visible	2026-10-09 10:00:00.493495+05:30
35c2702a-61fc-4e65-a2ee-ba0cf228c610	\N	2026-10-09 10:00:00.522041+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	e4130151-2b46-40e5-b604-ed235045a782	0 documents visible	2026-10-09 10:00:00.522041+05:30
e5364ac1-8168-4084-98fb-f4e6a42ff554	\N	2026-10-09 10:00:12.012494+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	e4130151-2b46-40e5-b604-ed235045a782	0 documents visible	2026-10-09 10:00:12.012494+05:30
12999f11-1f8a-477f-b764-5d3f8f291c3c	\N	2026-10-09 10:00:12.03292+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	e4130151-2b46-40e5-b604-ed235045a782	0 documents visible	2026-10-09 10:00:12.03292+05:30
8a3def6b-7609-4b22-ab2a-a498ce491238	\N	2026-10-09 10:00:38.850773+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	e4130151-2b46-40e5-b604-ed235045a782	0 documents visible	2026-10-09 10:00:38.850773+05:30
ee308622-b1bb-42c8-bcb9-a91985dfb28a	\N	2026-10-09 10:00:38.888811+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	e4130151-2b46-40e5-b604-ed235045a782	0 documents visible	2026-10-09 10:00:38.888811+05:30
99268c72-46bc-499c-bf0c-19dac727e712	\N	2026-10-09 10:00:47.28346+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-09 10:00:47.28346+05:30
653264aa-5b8a-4453-8844-478915ebcb4d	\N	2026-10-09 10:00:53.123102+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:00:53.123102+05:30
255c0340-04a7-40f3-9497-e9b424e20745	\N	2026-10-09 10:00:53.163008+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:00:53.163008+05:30
41b4610d-0c8c-4aba-8a03-0860acc2ef28	\N	2026-10-09 10:01:51.405816+05:30	\N	\N	update_access	document	doc-fad3ce481e4b	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	["admin", "hr", "manager"]	2026-10-09 10:01:51.405816+05:30
7f717380-35d0-4cbd-a9ad-dd973e014db0	\N	2026-10-09 10:10:07.627476+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	User system@gmailexample.com logged in successfully	2026-10-09 10:10:07.627476+05:30
40f1af6c-40de-42a1-8d8c-886f19b774dd	\N	2026-10-09 10:10:43.399494+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-09 10:10:43.399494+05:30
b111e68e-bc4a-492b-b940-057824efff36	\N	2026-10-09 10:11:38.216868+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:11:38.216868+05:30
2d07d1a2-23c2-4f5a-b964-51c228a086fd	\N	2026-10-09 10:11:38.25499+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:11:38.25499+05:30
03abf08a-317c-487c-971f-b956bcfc24c2	\N	2026-10-09 10:13:47.695058+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:13:47.695058+05:30
74b5dd83-e486-448e-a0e0-dfc770fc0a3c	\N	2026-10-09 10:13:47.765104+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:13:47.765104+05:30
2556b16e-06a3-4cd8-88e8-7df5283620ea	\N	2026-10-09 10:14:03.515595+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:14:03.515595+05:30
89aab837-b5a8-4f4f-89cc-ec1cfa2b26fd	\N	2026-10-09 10:14:03.545397+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:14:03.545397+05:30
6fccfb12-291c-4198-be3d-95c6a7cacbd3	\N	2026-10-09 10:14:10.762126+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:14:10.762126+05:30
d26a6c56-9967-4edf-b1ba-9b8426d1f45d	\N	2026-10-09 10:18:25.147731+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:18:25.147731+05:30
464ea884-2bbb-4b26-bf93-460c9dd99305	\N	2026-10-09 10:18:25.230221+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:18:25.230221+05:30
58a3271a-c885-4328-bfa7-3377a82d6b2c	\N	2026-10-09 10:18:51.278392+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:18:51.278392+05:30
d0f33944-5a9b-43af-8d55-30049d2d66fd	\N	2026-10-09 10:19:01.703667+05:30	\N	\N	update_access	document	doc-9a4395663625	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	["admin", "hr", "finance", "employee"]	2026-10-09 10:19:01.703667+05:30
ae5e031d-cad0-455b-967a-e241552844b2	\N	2026-10-09 10:14:10.851288+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:14:10.851288+05:30
3d7afc56-b35a-419c-ba2a-ec89764f6b6d	\N	2026-10-09 10:18:51.318794+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:18:51.318794+05:30
d1876ccb-624e-428e-879c-e9cf46e02d2a	\N	2026-10-09 10:21:50.062651+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:21:50.062651+05:30
89c76993-fefe-4ed6-af91-62eb43e457a8	\N	2026-10-09 10:21:50.170441+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:21:50.170441+05:30
cc489220-fb4a-4687-a01a-49a170482575	\N	2026-10-09 10:26:09.240885+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:26:09.240885+05:30
d77eabe5-a695-4e9c-8303-311af4b2f73c	\N	2026-10-09 10:26:09.362929+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:26:09.362929+05:30
42a29ba0-ab5b-42e4-9058-a9b62be3961c	\N	2026-10-09 10:27:35.895206+05:30	\N	\N	update_user	user	d943dcaf-f69f-4476-9d47-ed6a852613f5	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	Updated user system@gmailexample.com (Role Key: system_admin, Rank Level: 0)	2026-10-09 10:27:35.895206+05:30
3f4dabad-3c45-49d3-9183-e6e072c17048	\N	2026-10-09 10:27:42.675231+05:30	\N	\N	update_user	user	d943dcaf-f69f-4476-9d47-ed6a852613f5	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	Updated user system@gmailexample.com (Role Key: system_admin, Rank Level: 0)	2026-10-09 10:27:42.675231+05:30
39c60de1-2364-4810-98f0-c4e2c058aa92	\N	2026-10-09 10:27:51.95131+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:27:51.95131+05:30
3c56c14c-9117-4e75-9887-7f2f99ca94dd	\N	2026-10-09 10:27:52.044707+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:27:52.044707+05:30
b662026d-c154-4fb2-8bd6-6f28576aadbb	\N	2026-10-09 10:32:11.590052+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	37c04645-a76d-42d9-9c90-84da82849115	User employee@example.com logged in successfully	2026-10-09 10:32:11.590052+05:30
68d0a572-d448-4e91-9ad0-5b48a87cb8ed	\N	2026-10-09 10:35:06.881329+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-09 10:35:06.881329+05:30
de655106-9e25-4890-8227-f0f4afa1bac0	\N	2026-10-09 10:35:21.321885+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:35:21.321885+05:30
ea15a785-0f59-431c-b609-7a7c007d5541	\N	2026-10-09 10:35:21.363508+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:35:21.363508+05:30
96af294d-512c-4b3c-9379-5dbcc1df21c2	\N	2026-10-09 10:39:02.22457+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:39:02.22457+05:30
f40862ee-ff52-4ba0-93ff-081363dd99ca	\N	2026-10-09 10:39:02.270409+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:39:02.270409+05:30
e3a67194-d443-4db9-a3d2-3faf7c7d8eee	\N	2026-10-09 10:39:50.0955+05:30	\N	\N	update_user	user	d943dcaf-f69f-4476-9d47-ed6a852613f5	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	Updated user system@gmailexample.com (Role Key: manager, Rank Level: 3)	2026-10-09 10:39:50.0955+05:30
7758cd1e-6f2d-4d00-bc80-4f497993e1f3	\N	2026-10-09 10:40:39.434082+05:30	\N	\N	update_user	user	d943dcaf-f69f-4476-9d47-ed6a852613f5	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	Updated user system@gmailexample.com (Role Key: team_lead, Rank Level: 3)	2026-10-09 10:40:39.434082+05:30
5790eccc-fdcb-4b7b-8f91-8316adcb4ad6	\N	2026-10-09 10:45:55.59158+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:45:55.59158+05:30
74e3add5-0787-42c0-81a4-320ece315cb7	\N	2026-10-09 10:45:55.617026+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:45:55.617026+05:30
00c3d67b-b05c-4dc0-a3fc-366b806f2d0a	a3424830-6d45-4ad8-a43b-a5fdf70d691d	2026-10-09 10:54:43.856513+05:30	\N	\N	change_password	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	User admin@acmecorp.com successfully updated their account password.	2026-10-09 10:54:43.856513+05:30
b8d73bfc-2343-49ac-a236-c9c9b8b52b67	a3424830-6d45-4ad8-a43b-a5fdf70d691d	2026-10-09 10:54:44.286906+05:30	\N	\N	change_password	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	User admin@acmecorp.com successfully updated their account password.	2026-10-09 10:54:44.286906+05:30
ee82845f-8fed-40a7-a7ca-ffb1d42cabd3	\N	2026-10-09 10:54:44.678689+05:30	\N	\N	update_hierarchy_role	company_role	lead_ai_architect	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	Updated role 'Lead AI Architect' (Rank Level 3)	2026-10-09 10:54:44.678689+05:30
ed02ecd1-4e5b-4192-883a-e2bf73f66b1d	a3424830-6d45-4ad8-a43b-a5fdf70d691d	2026-10-09 10:54:58.738923+05:30	\N	\N	change_password	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	User admin@acmecorp.com successfully updated their account password.	2026-10-09 10:54:58.738923+05:30
e167f793-8dbe-4ceb-9c7b-382e94eff23d	a3424830-6d45-4ad8-a43b-a5fdf70d691d	2026-10-09 10:54:59.190526+05:30	\N	\N	change_password	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	User admin@acmecorp.com successfully updated their account password.	2026-10-09 10:54:59.190526+05:30
2fe95921-d88d-45ab-9e89-211946dc8a0f	\N	2026-10-09 10:54:59.615052+05:30	\N	\N	update_hierarchy_role	company_role	lead_ai_architect	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	Updated role 'Lead AI Architect' (Rank Level 3)	2026-10-09 10:54:59.615052+05:30
805bcb23-a344-494c-953c-2776cfd4884e	a3424830-6d45-4ad8-a43b-a5fdf70d691d	2026-10-09 10:54:59.620579+05:30	\N	\N	create_user	user	750bfb86-90ed-4754-94fa-abb6ed3713b6	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	Created user employee_test@acmecorp.com with role 'employee' (Rank Level 4)	2026-10-09 10:54:59.620579+05:30
0e74bb37-c7a5-40d6-81fe-a59f3bfc683e	a3424830-6d45-4ad8-a43b-a5fdf70d691d	2026-10-09 10:54:59.824367+05:30	\N	\N	update_user	user	750bfb86-90ed-4754-94fa-abb6ed3713b6	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	Updated user employee_test@acmecorp.com (Role Key: lead_ai_architect, Rank Level: 3)	2026-10-09 10:54:59.824367+05:30
17b8a23c-8941-4428-9172-55b4c56bf47e	\N	2026-10-09 10:57:01.231375+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	17 documents visible	2026-10-09 10:57:01.231375+05:30
05a93b3c-65e1-4a70-a094-3834a2de835f	\N	2026-10-09 11:02:44.970199+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	8fdffb04-e6c2-4c1c-8813-1e9a0767e82e	User hr@example.com logged in successfully	2026-10-09 11:02:44.970199+05:30
0373b62d-5437-4986-a207-be85e705147c	\N	2026-10-10 13:04:59.250266+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	61bdc8eb-3dd9-4383-9c10-91bb052e7207	User admin@example.com logged in successfully	2026-10-10 13:04:59.250266+05:30
a2c3c538-2339-40da-800a-f2220fbcd9ed	\N	2026-10-10 13:08:12.404035+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	8fdffb04-e6c2-4c1c-8813-1e9a0767e82e	User hr@example.com logged in successfully	2026-10-10 13:08:12.404035+05:30
d9b436f5-9f9b-41a9-bd6b-de5279dc0e5b	\N	2026-10-10 13:14:00.299091+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	User system@gmailexample.com logged in successfully	2026-10-10 13:14:00.299091+05:30
a91ef00c-2cb5-4fbf-9197-b1e829396363	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 13:14:54.63044+05:30	\N	\N	login_failed	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	\N	Failed login attempt for email admin@apex.com	2026-10-10 13:14:54.63044+05:30
a9fe246a-8d5c-4bc5-9cec-bf38bb8fd179	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 13:15:06.5567+05:30	\N	\N	login_failed	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	\N	Failed login attempt for email admin@apex.com	2026-10-10 13:15:06.5567+05:30
371d4289-a315-41ea-8137-9e53e71200ff	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 13:15:27.05425+05:30	\N	\N	password_reset_request	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Reset request for admin@apex.com	2026-10-10 13:15:27.05425+05:30
809d4dd1-0c8d-4b53-a91b-b753b87a2bd0	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 13:15:31.894266+05:30	\N	\N	password_reset_request	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Reset request for admin@apex.com	2026-10-10 13:15:31.894266+05:30
a4a1cdff-c050-45c8-8775-63a717a84934	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 13:16:02.7022+05:30	\N	\N	login_failed	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	\N	Failed login attempt for email admin@apex.com	2026-10-10 13:16:02.7022+05:30
36be360f-6333-419b-9b7a-2f94ff423ee4	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 13:17:10.469998+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 13:17:10.469998+05:30
eb58d014-7e7a-4334-9f1d-e335dd830d39	\N	2026-10-10 13:19:33.391283+05:30	\N	\N	login_failed	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	\N	Failed login attempt for email test@example.com	2026-10-10 13:19:33.391283+05:30
80f6b3ad-a6ad-4240-96a0-0fd195885740	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 13:19:53.298022+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 13:19:53.298022+05:30
4fafbe51-0c79-4ef6-a71f-93cc08585482	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 14:09:35.10121+05:30	\N	\N	change_password	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com successfully updated their account password.	2026-10-10 14:09:35.10121+05:30
392dd20f-a7ba-4206-88b1-0dd34cf4b298	\N	2026-10-10 14:28:28.551639+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	1 documents visible	2026-10-10 14:28:28.551639+05:30
35481ad5-6d93-4fcf-8e60-cea4da30bba1	\N	2026-10-10 14:28:28.569976+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	1 documents visible	2026-10-10 14:28:28.569976+05:30
f85e2860-9b32-41cb-8452-38f0ccad9696	\N	2026-10-10 14:36:12.259767+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	1 documents visible	2026-10-10 14:36:12.259767+05:30
0baa014e-9ae9-4560-b733-6c59ca780f30	\N	2026-10-10 14:36:12.2787+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	1 documents visible	2026-10-10 14:36:12.2787+05:30
d30fd793-1e51-4692-b207-f93a66f7c26b	\N	2026-10-10 14:36:31.227381+05:30	\N	\N	update_hierarchy_role	company_role	finance	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Updated role 'Finance' (Rank Level 2)	2026-10-10 14:36:31.227381+05:30
149f6534-5f3b-431d-b1bf-46dce7902307	\N	2026-10-10 16:08:34.921819+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:08:34.921819+05:30
568f8a0d-2384-4929-8f69-4f66a0a42ee0	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 14:38:37.646536+05:30	\N	\N	create_user	user	28d51557-7454-4964-9a70-5a74ce356302	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Created user hetvifin@apex.com (Hetvi) with role 'finance' (Rank Level 2)	2026-10-10 14:38:37.646536+05:30
d0b73e26-57ee-4ec9-aae5-822fd0aefd38	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 14:40:17.99593+05:30	\N	\N	create_user	user	e65ce168-7a61-404e-9068-dfb537a03fd0	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Created user hetvifinance@apex.com (Hetvi Taank) with role 'finance' (Rank Level 2)	2026-10-10 14:40:17.99593+05:30
98b91d91-d4ff-4bb2-ba7b-469355691eb9	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 14:49:46.719364+05:30	\N	\N	create_user	user	9d06613c-0fcd-4a5c-955e-90713bc39693	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Created user finHetvi@apex.com (Hetvi Taank) with role 'finance' (Rank Level 2)	2026-10-10 14:49:46.719364+05:30
28a40e32-71e8-4084-b0ac-1806f2cd94b1	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 14:53:27.620355+05:30	\N	\N	create_user	user	2c540497-a8db-40bb-87f7-5ba3641eada7	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Created user hetvifin1@apex.com (Hetvi Taank) with role 'finance' (Rank Level 2)	2026-10-10 14:53:27.620355+05:30
9a27fd52-ae0c-494b-b844-32b67733038d	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 14:55:07.505013+05:30	\N	\N	create_user	user	fd04d806-81e6-45ac-a9ba-c4e431347c1f	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Created user trushafin@apex.com (trusha) with role 'finance' (Rank Level 2)	2026-10-10 14:55:07.505013+05:30
25ff0dba-3c59-4abd-9d16-18287766e029	\N	2026-10-10 14:59:41.507599+05:30	\N	\N	update_hierarchy_role	company_role	social_media	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Updated role 'Social media' (Rank Level 6)	2026-10-10 14:59:41.507599+05:30
da8bff9b-cd05-45f2-9868-592af2e706d0	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:04:39.748781+05:30	\N	\N	create_user	user	aad9d995-6915-42cb-b69c-2a4b81ac2fb4	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Created user test_employee_verify@apex.com (Verified User) with role 'finance' (Rank Level 2)	2026-10-10 15:04:39.748781+05:30
8713a6ca-93c0-491f-899d-dae04cb48ed5	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:06:21.298762+05:30	\N	\N	delete_user	user	28d51557-7454-4964-9a70-5a74ce356302	\N	\N	\N	\N	{}	\N	\N	WARNING	a333efea-a6ac-461f-9639-0a06153c37da	Deleted user hetvifin@apex.com (Hetvi)	2026-10-10 15:06:21.298762+05:30
151b0d65-edf1-498b-8b60-acd3adb0ae80	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:07:22.491137+05:30	\N	\N	create_user	user	30f3a38d-c45a-4b97-b56f-e20c55e949a6	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Created user del_test@apex.com (Del Test) with role 'finance' (Rank Level 2)	2026-10-10 15:07:22.491137+05:30
a4fb06b7-e0d6-49e0-ae32-1ed35ecd9af6	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:07:22.71388+05:30	\N	\N	delete_user	user	30f3a38d-c45a-4b97-b56f-e20c55e949a6	\N	\N	\N	\N	{}	\N	\N	WARNING	a333efea-a6ac-461f-9639-0a06153c37da	Deleted user del_test@apex.com (Del Test)	2026-10-10 15:07:22.71388+05:30
d8e38082-dc68-4334-bd18-31286365775b	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:08:53.188209+05:30	\N	\N	create_user	user	995b4d06-051f-48eb-b255-91d7ba54dd18	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Created user purvahead@apex.com (purva) with role 'hr' (Rank Level 2)	2026-10-10 15:08:53.188209+05:30
077a01a6-c8f0-4b50-b1f0-71cbc398dd7b	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:09:57.125109+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	995b4d06-051f-48eb-b255-91d7ba54dd18	User purvahead@apex.com logged in successfully	2026-10-10 15:09:57.125109+05:30
9021e400-9d1b-42bb-8865-5644f2e05b57	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:10:49.173104+05:30	\N	\N	change_password	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	995b4d06-051f-48eb-b255-91d7ba54dd18	User purvahead@apex.com successfully updated their account password.	2026-10-10 15:10:49.173104+05:30
adf1cec1-e6cf-4299-8149-d4a987329faf	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:12:09.970425+05:30	\N	\N	login_failed	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	\N	Failed login attempt for email purvahead@apex.com	2026-10-10 15:12:09.970425+05:30
392f507d-f1c3-47f4-992f-966e75be49d8	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:12:18.296665+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	995b4d06-051f-48eb-b255-91d7ba54dd18	User purvahead@apex.com logged in successfully	2026-10-10 15:12:18.296665+05:30
1c45c531-e7f1-4d35-9603-654f6e00ab5d	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:16:01.564152+05:30	\N	\N	login_failed	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	\N	Failed login attempt for email admin@apex.com	2026-10-10 15:16:01.564152+05:30
7b7c222a-538d-4a1c-88f9-b1fa2ec81634	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:16:08.626264+05:30	\N	\N	login_failed	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	\N	Failed login attempt for email admin@apex.com	2026-10-10 15:16:08.626264+05:30
afc71f88-68e5-44d4-b30f-de969bbf460f	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:16:14.39631+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 15:16:14.39631+05:30
49f8d7ba-a729-4c33-a686-ff833308d06a	\N	2026-10-10 15:17:11.736209+05:30	\N	\N	update_hierarchy_role	company_role	ee	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Updated role 'EE' (Rank Level 4)	2026-10-10 15:17:11.736209+05:30
9cca92fc-5ca0-40b6-8848-b1aa1df95199	\N	2026-10-10 15:17:16.059083+05:30	\N	\N	delete_hierarchy_role	company_role	14	\N	\N	\N	\N	{}	\N	\N	WARNING	a333efea-a6ac-461f-9639-0a06153c37da	Removed role 'EE' from hierarchy.	2026-10-10 15:17:16.059083+05:30
c281dcdb-3d8b-4862-93a9-c2078a72bdd4	\N	2026-10-10 15:17:30.221398+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	1 documents visible	2026-10-10 15:17:30.221398+05:30
6d2dfbf6-0c27-4dc1-91dd-97f874fb0837	\N	2026-10-10 15:17:30.236596+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	1 documents visible	2026-10-10 15:17:30.236596+05:30
6b8bee65-bd7d-4cb6-9b6e-d2c597908703	\N	2026-10-10 15:37:21.990889+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	1 documents visible	2026-10-10 15:37:21.990889+05:30
ef4ff474-edcb-472a-ba7e-69488610e6ee	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:39:13.116603+05:30	\N	\N	login_failed	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	\N	Failed login attempt for email admin@apex.com	2026-10-10 15:39:13.116603+05:30
954ed4a5-ead9-4a12-9f8c-6f91168c6e3d	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:39:59.181599+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 15:39:59.181599+05:30
caa64468-5c2d-42b2-b488-a78e72e4f5c5	\N	2026-10-10 15:40:32.312492+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	1 documents visible	2026-10-10 15:40:32.312492+05:30
badcc061-01b0-4361-b0a8-b2d6823345ef	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:41:00.126219+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 15:41:00.126219+05:30
c985917a-f263-4499-8e8e-6e1cbce4817f	\N	2026-10-10 15:41:00.548304+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	1 documents visible	2026-10-10 15:41:00.548304+05:30
1b07d9f6-a899-48a1-9469-27d4687dabfb	\N	2026-10-10 15:41:00.576407+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	1 documents visible	2026-10-10 15:41:00.576407+05:30
08d147cd-5b52-408e-9545-a9eb53137286	\N	2026-10-10 15:41:05.711131+05:30	\N	\N	delete	document	doc-4f6b31669049	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	\N	2026-10-10 15:41:05.711131+05:30
e957836d-e6fa-4453-b1f6-58eeb1752c1c	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:52:23.455515+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 15:52:23.455515+05:30
fa52104b-65c6-41d3-8c29-925180b7eb0c	\N	2026-10-10 15:53:29.036895+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	0 documents visible	2026-10-10 15:53:29.036895+05:30
6573e673-5333-42fd-8f74-53f50e5383ba	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:53:40.927483+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 15:53:40.927483+05:30
44c3c3c6-a19c-4b28-9cca-c062374dd209	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:53:55.004422+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 15:53:55.004422+05:30
6de70f92-462d-4ce5-bee9-200baa226d74	\N	2026-10-10 15:53:55.206826+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	0 documents visible	2026-10-10 15:53:55.206826+05:30
0f535c71-29d9-420e-b11c-8d1ec16d0fff	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 15:59:49.725645+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 15:59:49.725645+05:30
4216ed2b-08c5-4da3-b421-bfdd00efc823	\N	2026-10-10 16:04:53.710791+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	11 documents visible	2026-10-10 16:04:53.710791+05:30
2773b05e-186a-4519-8fbd-5fb8ec785a52	\N	2026-10-10 16:04:53.77911+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	11 documents visible	2026-10-10 16:04:53.77911+05:30
2023cbb9-d304-4fc2-a4b4-114029e6fd09	\N	2026-10-10 16:05:26.57985+05:30	\N	\N	create_drive_link	drive_link	1	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	https://drive.google.com/drive/folders/1I9x9ihja3-FIVT7urWgZsTKWWvU4kjE7?usp=drive_link	2026-10-10 16:05:26.57985+05:30
c4e3cc86-a5f9-455c-955f-a6f471e93c9c	\N	2026-10-10 16:06:37.788639+05:30	\N	\N	sync_drive_link	drive_link	1	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	\N	2026-10-10 16:06:37.788639+05:30
32ca3020-c273-48da-82e7-4e7517d7cf28	\N	2026-10-10 16:06:48.365701+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:06:48.365701+05:30
748e1771-b122-405e-a19f-d7ee7ad7dc16	\N	2026-10-10 16:06:48.438693+05:30	\N	\N	update_access	document	doc-d6402dc16e20	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	roles: ['admin', 'manager', 'employee', 'hr'], denied: ['purvahead@apex.com']	2026-10-10 16:06:48.438693+05:30
dca7283b-4392-4681-bd76-c3d97c134ac1	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 16:07:13.803375+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 16:07:13.803375+05:30
6359e56a-c63e-4400-bfb0-31bc81b6d71f	\N	2026-10-10 16:07:14.007959+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:07:14.007959+05:30
3a15d3fe-7416-4b72-8159-624649e61095	\N	2026-10-10 16:08:34.886776+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:08:34.886776+05:30
b3cbce22-fac1-42b9-af9d-3c7336b98d35	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 16:09:11.50558+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 16:09:11.50558+05:30
2f589eec-0e9f-44f5-9f72-911250073ce3	\N	2026-10-10 16:09:11.718638+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:09:11.718638+05:30
54e8b012-6f87-44bd-b9f5-84f93b97ecfb	\N	2026-10-10 16:14:35.309051+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:14:35.309051+05:30
f396e08a-c81f-495b-acb8-d53cba2da411	\N	2026-10-10 16:14:35.378272+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:14:35.378272+05:30
27e69232-8282-4a69-a13d-ae24e38e5727	\N	2026-10-10 16:29:35.916538+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	User system@gmailexample.com logged in successfully	2026-10-10 16:29:35.916538+05:30
c1cfdb0a-46b8-4bc2-ba9e-264b19c85f58	a3424830-6d45-4ad8-a43b-a5fdf70d691d	2026-10-10 16:29:57.216168+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	User admin@acmecorp.com logged in successfully	2026-10-10 16:29:57.216168+05:30
5fadab79-de7e-4aa6-b168-1bfa3843ac0d	\N	2026-10-10 16:29:57.622592+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	1 documents visible	2026-10-10 16:29:57.622592+05:30
83cd3100-41aa-49ba-b27e-1db7bc3e1d22	\N	2026-10-10 16:29:57.657504+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	1 documents visible	2026-10-10 16:29:57.657504+05:30
4c681d98-91a0-4790-bd05-79f6351cbadc	\N	2026-10-10 16:30:13.02094+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	1 documents visible	2026-10-10 16:30:13.02094+05:30
b2746c90-7218-404b-b51b-597e08a79524	\N	2026-10-10 16:30:13.070641+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	1 documents visible	2026-10-10 16:30:13.070641+05:30
95892851-31a2-411e-9088-fa59f54d5c79	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 16:30:32.235863+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 16:30:32.235863+05:30
89716b57-9962-483c-ab7f-7e1dc824c5ed	\N	2026-10-10 16:30:45.103835+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:30:45.103835+05:30
07024794-aaca-4579-bde9-efe4370d24cd	\N	2026-10-10 16:30:45.17+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:30:45.17+05:30
9be60c52-7bb5-4bc7-a5dd-c5b479e37bc0	\N	2026-10-10 16:31:25.857044+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:31:25.857044+05:30
87169eea-ad05-471b-9b71-24c236d8abf0	\N	2026-10-10 16:31:25.920898+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:31:25.920898+05:30
4b03bc02-c084-4203-8590-9fffa1aad6de	\N	2026-10-10 16:31:30.917159+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:31:30.917159+05:30
2732d6f5-bc20-4cbd-a31d-3ea6d64c8cd7	\N	2026-10-10 16:31:30.978929+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	15 documents visible	2026-10-10 16:31:30.978929+05:30
7f768956-7822-4d4e-9f75-8588392d2fa8	\N	2026-10-10 16:31:54.432522+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	16 documents visible	2026-10-10 16:31:54.432522+05:30
7f3bd32e-982f-4ac9-9271-c096b5f1fe53	\N	2026-10-10 16:31:54.519813+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	16 documents visible	2026-10-10 16:31:54.519813+05:30
655a1493-6a93-4b4a-a008-f0a943c2ad83	\N	2026-10-10 16:32:51.677894+05:30	\N	\N	sync_drive_link	drive_link	1	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	\N	2026-10-10 16:32:51.677894+05:30
c34087a2-a70d-478a-9f68-c13ad8fcfec0	\N	2026-10-10 16:33:00.585884+05:30	\N	\N	sync_drive_link	drive_link	1	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	\N	2026-10-10 16:33:00.585884+05:30
7ca4c2c2-a42f-4f2e-b501-d54d353b282d	\N	2026-10-10 16:33:26.76189+05:30	\N	\N	sync_drive_link	drive_link	1	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	\N	2026-10-10 16:33:26.76189+05:30
cb49d06c-b20a-4d52-a942-acda0316a051	\N	2026-10-10 16:33:29.407033+05:30	\N	\N	sync_drive_link	drive_link	1	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	\N	2026-10-10 16:33:29.407033+05:30
f7135465-cdcd-4b54-9485-52b650d7550e	\N	2026-10-10 16:33:29.828268+05:30	\N	\N	sync_drive_link	drive_link	1	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	\N	2026-10-10 16:33:29.828268+05:30
244dac02-925c-4201-8126-2e63448d779f	\N	2026-10-10 16:33:35.132416+05:30	\N	\N	sync_drive_link	drive_link	1	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	\N	2026-10-10 16:33:35.132416+05:30
2ea6c156-0c2e-40d1-a7be-91eb6948bc72	\N	2026-10-10 16:33:35.699492+05:30	\N	\N	sync_drive_link	drive_link	1	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	\N	2026-10-10 16:33:35.699492+05:30
47206408-2137-43bb-9df2-8d48e4172f34	\N	2026-10-10 16:33:35.878551+05:30	\N	\N	sync_drive_link	drive_link	1	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	\N	2026-10-10 16:33:35.878551+05:30
a38334bb-7d7e-4224-85c2-569eb6a58208	\N	2026-10-10 16:38:06.214541+05:30	\N	\N	update_access	document	doc-ff2f2247df35	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	roles: ['admin', 'hr', 'finance', 'manager', 'employee'], denied: []	2026-10-10 16:38:06.214541+05:30
53408384-4be8-48df-9f8d-e6495944629f	\N	2026-10-10 16:38:16.267087+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	16 documents visible	2026-10-10 16:38:16.267087+05:30
0761187a-9dc5-44a1-86a7-545bc90ba46e	\N	2026-10-10 16:38:16.362272+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	16 documents visible	2026-10-10 16:38:16.362272+05:30
7a56293a-6c5f-4398-8428-52697b5f42cb	\N	2026-10-10 16:50:03.97035+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	User system@gmailexample.com logged in successfully	2026-10-10 16:50:03.97035+05:30
b57176a7-0014-45a0-8a14-6ee8023c9450	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 16:50:32.249319+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 16:50:32.249319+05:30
5b56362b-f6cf-4b7d-84d5-7e95fd1782c0	\N	2026-10-10 16:51:20.035573+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	16 documents visible	2026-10-10 16:51:20.035573+05:30
9f8e81a6-a57b-425c-8029-2d32c0318745	\N	2026-10-10 16:51:20.15348+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	16 documents visible	2026-10-10 16:51:20.15348+05:30
baef35ad-fddb-4bab-9304-04dd8d63ba44	\N	2026-10-10 16:51:42.85437+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	16 documents visible	2026-10-10 16:51:42.85437+05:30
29e38c7f-4da9-44ec-b7c9-a7d2c24f19e9	\N	2026-10-10 16:51:43.05048+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	16 documents visible	2026-10-10 16:51:43.05048+05:30
36c72ff1-4420-4a9f-89b0-56a99add47fe	\N	2026-10-10 16:53:42.927609+05:30	\N	\N	update_access	document	doc-f5e24b39a009	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	roles: ['admin', 'finance', 'manager', 'employee', 'hr'], denied: ['purvahead@apex.com']	2026-10-10 16:53:42.927609+05:30
0ecee977-738e-4b0c-a3a1-9522e2e0e587	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 16:56:46.567014+05:30	\N	\N	update_user	user	a333efea-a6ac-461f-9639-0a06153c37da	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	Updated user admin@apex.com (Role Key: admin, Rank Level: 1)	2026-10-10 16:56:46.567014+05:30
2babee76-9b36-4a09-9e24-d90e9c15d766	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 16:59:37.422701+05:30	\N	\N	login_blocked	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	a333efea-a6ac-461f-9639-0a06153c37da	Deactivated user admin@apex.com attempted login	2026-10-10 16:59:37.422701+05:30
ae06805f-1d79-472a-9a64-5f7f86703cff	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 16:59:43.355333+05:30	\N	\N	login_blocked	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	a333efea-a6ac-461f-9639-0a06153c37da	Deactivated user admin@apex.com attempted login	2026-10-10 16:59:43.355333+05:30
21d69c2f-3165-4a24-b01c-f774edb79220	\N	2026-10-10 17:00:22.343813+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	User system@gmailexample.com logged in successfully	2026-10-10 17:00:22.343813+05:30
f4a8e1e3-8904-429d-88d5-9307c412f3a2	a3424830-6d45-4ad8-a43b-a5fdf70d691d	2026-10-10 17:00:55.086777+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	User admin@acmecorp.com logged in successfully	2026-10-10 17:00:55.086777+05:30
ef9aaf6f-0b35-4e6b-a86c-daa6844e8a53	\N	2026-10-10 17:01:00.133937+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	1 documents visible	2026-10-10 17:01:00.133937+05:30
20ccbc27-e8da-43c3-993b-09e640f7e159	\N	2026-10-10 17:01:00.191957+05:30	\N	\N	view	document_library	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	1 documents visible	2026-10-10 17:01:00.191957+05:30
6dcd7b25-1ad6-4cde-b659-ca0e6653d230	a3424830-6d45-4ad8-a43b-a5fdf70d691d	2026-10-10 17:01:50.354852+05:30	\N	\N	create_user	user	6655cfe1-5ffd-4db2-907d-d2627066a714	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	Created user hetvi@admin.com (hetvi) with role 'finance' (Rank Level 2)	2026-10-10 17:01:50.354852+05:30
222ee13e-0f49-41af-87a2-80a448d9f4a1	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 17:11:57.772302+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 17:11:57.772302+05:30
8def0f1c-edf2-4c35-89d7-d67b7e8e4ea8	a3424830-6d45-4ad8-a43b-a5fdf70d691d	2026-10-10 17:11:57.981344+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	User admin@acmecorp.com logged in successfully	2026-10-10 17:11:57.981344+05:30
6756f5ed-595b-4ab7-aff3-cfbb296a5044	69bb5e9f-858a-4cdc-a6f4-e05b1a80494b	2026-10-10 17:11:58.186115+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	e4130151-2b46-40e5-b604-ed235045a782	User cmp3@example.com logged in successfully	2026-10-10 17:11:58.186115+05:30
1f707fb3-b8c0-43b2-bb15-543d8330bca8	\N	2026-10-10 17:11:58.390432+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	d943dcaf-f69f-4476-9d47-ed6a852613f5	User system@gmailexample.com logged in successfully	2026-10-10 17:11:58.390432+05:30
11f318b1-c183-4a53-8ec9-6a56d6f38213	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 17:12:59.072224+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	a333efea-a6ac-461f-9639-0a06153c37da	User admin@apex.com logged in successfully	2026-10-10 17:12:59.072224+05:30
4f6c57a1-1e1a-4dde-a23b-87ce1412ffe0	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 17:14:24.814674+05:30	\N	\N	login_failed	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	\N	Failed login attempt for email purvahead@apex.com	2026-10-10 17:14:24.814674+05:30
bc18e5f0-e754-4891-9453-437c905c70ac	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 17:14:30.787823+05:30	\N	\N	login_failed	auth	\N	\N	\N	\N	\N	{}	\N	\N	WARNING	\N	Failed login attempt for email purvahead@apex.com	2026-10-10 17:14:30.787823+05:30
b9888c9c-b834-4490-b541-88c7141139ae	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 17:14:39.206704+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	995b4d06-051f-48eb-b255-91d7ba54dd18	User purvahead@apex.com logged in successfully	2026-10-10 17:14:39.206704+05:30
3fc7a2cc-dcac-47c6-b436-a3a565ea7225	df672f52-b432-45f1-b1a6-4b4b78e23065	2026-10-10 18:43:43.095215+05:30	\N	\N	login_success	auth	\N	\N	\N	\N	\N	{}	\N	\N	INFO	995b4d06-051f-48eb-b255-91d7ba54dd18	User purvahead@apex.com logged in successfully	2026-10-10 18:43:43.095215+05:30
\.


--
-- Data for Name: chunks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.chunks (id, tenant_id, document_id, version_id, project_id, chunk_index, page_start, page_end, section_path, text, text_hash, embedding_model, index_state, created_at) FROM stdin;
6bcaacb4-a0e3-41d4-b81e-901deaa5c70d	tenant-001	doc-0718297b71e4	ver-77bab82c	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nCode of Employee Conduct\nDocument ID NXR-HR-POL-009\nVersion 3.1\nEffective 1 April 2026\nDate\nOwner Head of HR with Legal & Compliance (Adv. Pooja\nNair)\nApplies To All employees, interns, contractors and consultants\n1. Our Values\nIntegrity. Customer First. Continuous Learning. Ownership.\nRespect. This Code explains how we apply these values every day.\n2. Workplace Behaviour\n• Treat colleagues, clients and vendors with courtesy, regardless of\nrole, gender, religion, caste, age, disability, sexual orientation,\nnationality or background.\n• Communicate professionally in meetings, Teams chats, emails\nand code reviews. Constructive disagreement is welcome;\npersonal attacks are not.	570119aa9564264a1b3117aa44f987ccd4c3d7ac35be47295f865c6d3de7251b	gemini-embedding-2	indexed	2026-10-08 15:06:46.428969
2aa94082-27e3-4807-a991-f00af7420ece	tenant-001	doc-0718297b71e4	ver-77bab82c	project-001	1	2	2	Page 2	• Be punctual, prepared and reliable. Keep commitments made to\nteammates and clients.\n• Dress code is business casual; client-facing days follow client site\nrules.\n• Alcohol, tobacco and illegal substances are not allowed on\ncompany premises or at company events held on premises.\n• Use company resources (laptop, internet, licences) primarily for\nbusiness.\n3. Ethics and Integrity\n• Be honest in reports, timesheets, expense claims and client\ncommunication.\n• Do not accept or offer bribes, kickbacks or improper benefits.\nGifts from vendors or clients above ₹3,000 in value must be\ndeclared to your manager and the Compliance team and may\nneed to be returned.\n• Respect intellectual property. Do not use pirated software or copy\ncode or content without licence.\n• Protect confidential information about Nexora, its clients and\ncolleagues during and after employment.\n• Follow all applicable laws, including anti-corruption, data\nprotection and labour laws.\n• Whistleblower protection: Concerns about fraud, financial\nmisreporting or serious misconduct can be raised confidentially at\nethics@nexora-tech.example. Retaliation against anyone who\nreports in good faith is prohibited.\n4. Conflicts of Interest\nA conflict arises when personal interests could influence, or appear to\ninfluence, your work decisions.\nSituation Rule	b231ed22ffb0b9c1c9fec20a0da2269543797961616a06188b756f75ace22895	gemini-embedding-2	indexed	2026-10-08 15:06:49.398472
30713b95-f0d2-4f62-a1f7-e3d3d584fd41	tenant-001	doc-0718297b71e4	ver-77bab82c	project-001	2	3	3	Page 3	Outside employment or Needs prior written approval; not\nfreelancing allowed with competitors or clients\nInvestment in vendors, Declare if holding more than 2% or any\nclients or competitors role in management\nRelatives working at Declare at joining; no direct reporting or\nNexora hiring influence over relatives\nHiring or buying from Must be declared and approved by the\nrelatives' firms Head of Compliance\nBoard or advisory positions Needs CEO approval\nelsewhere\nEmployees complete an annual conflict-of-interest declaration in\nPeopleHub by 30 April.\n5. Prevention of Sexual Harassment (POSH)\nNexora has zero tolerance for sexual harassment, as defined by the\nSexual Harassment of Women at Workplace (Prevention, Prohibition\nand Redressal) Act, 2013, and extends the same standards to all\ngenders in this policy.\n• Prohibited conduct includes unwelcome physical contact, sexual\nremarks, jokes, messages, showing explicit material, and stalking.\n• Complaints may be made in writing to the Internal Committee\n(IC) at ic@nexora-tech.example within 3 months of the incident\n(extendable by 3 months).\n• The IC is chaired by a senior woman employee (Kavita Menon)\nwith an external member from an NGO.\n• Inquiry is completed within 90 days; confidentiality is maintained\nfor all parties.\n• Interim measures such as a change in reporting line or leave may\nbe offered during inquiry.\n6. Other Prohibited Conduct	b3b5a1cebf568a1f32fa8bb3cc81c98a9dc9ceee924fc00a027c9780c72e2655	gemini-embedding-2	indexed	2026-10-08 15:06:50.255376
57dd3de4-1adc-4894-ba6d-a229ce10ee90	tenant-001	doc-0718297b71e4	ver-77bab82c	project-001	3	4	4	Page 4	Bullying, discrimination, violence or threats; theft or fraud; deliberate\ndamage to company property; sharing client or company data without\nauthorisation; use of social media to disclose confidential information or\ndisparage the company; and retaliation against complainants.\n7. Disciplinary Actions\nLevel Examples Possible Action\nMinor Repeated lateness, minor Verbal counselling or\npolicy breaches written warning\nModerate Misuse of resources, Final written warning;\nunprofessional behaviour, withholding increment\nfailure to disclose a conflict or bonus\nSerious Harassment, data leak, falsified Suspension,\nrecords, fraud, violence, termination, and legal\nrepeated moderate offences action where required\nProcess: (1) Allegation reported to HR; (2) Show-cause notice with 3\nworking days to reply; (3) Fact-finding by HR with Legal; (4) Decision\ncommunicated in writing within 15 working days; (5) Appeal to the Head\nof HR within 7 days of the decision.\nExample: An employee on Project Beacon is found to have submitted a\nfake taxi bill for ₹2,400. HR issues a show-cause notice, the employee\nadmits the error, repays the amount, and receives a final written\nwarning. A repeat would lead to termination.\n8. Acknowledgement\nEvery employee signs this Code at joining and acknowledges updates\nannually through PeopleHub.	71fd77dd106080c81c62035c29b28b40aa4cce653a31af6066201642fd408e27	gemini-embedding-2	indexed	2026-10-08 15:06:51.085487
0d93c35d-9d84-48a4-af15-2e5d64d73b19	tenant-001	doc-de573a503f6d	ver-56f14fd8	project-001	0	1	1	Page 1	Policy Title: Information Security & Data Protection Policy Purpose: To safeguard company data,\nsystems, and customer information against unauthorized access, breaches, and misuse. Scope:\nApplies to all employees, contractors, and third-party vendors.\nKey Points:\n• Password Management: Employees must use strong passwords (minimum 12\ncharacters, mix of letters, numbers, symbols). Passwords must be changed every 90\ndays.\n• Email Security: No sharing of confidential data via personal email. Phishing\nawareness training is mandatory.\n• Device Security: Company laptops must be encrypted and locked when unattended.\n• Network Usage: VPN required for remote access. Public Wi-Fi should be avoided\nunless secured.\n• Data Disposal: Sensitive documents must be shredded; digital files securely deleted.\n• Incident Reporting: Any suspected breach must be reported to IT Security within 1\nhour.\nEnforcement: Violations may result in disciplinary action, up to termination.	3ba63919eabfc31d2aa09d675753fefb9358ecb84aad29c7be3ce53216632541	gemini-embedding-2	indexed	2026-10-08 15:06:52.318835
6188ca42-364d-4edf-a2fa-e60389db1541	tenant-001	doc-03b90406eca2	ver-af1db78e	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Attendance Policy\nDocument ID NXR-HR-POL-002\nVersion 2.4\nEffective Date 1 April 2026\nOwner HR Operations (Rahul Deshmukh)\nApplies To All employees, including probationers and interns\n1. Purpose\nTo define working hours, attendance recording, late-arrival rules,\nabsence handling and overtime so that teams on projects such as Atlas,\nMeridian and Beacon can plan reliably.\n2. Working Hours\nItem Standard\nWorking days Monday to Friday\nStandard hours 9:30 AM – 6:30 PM (9 hours including a 1-hour\nbreak)	4442de7aeada298428a7fc310b08326599fc593045e9cba8d4c3a2e15fd32611	gemini-embedding-2	indexed	2026-10-08 15:06:53.488753
7be44522-d8cf-4521-83a2-102e59526a35	tenant-001	doc-03b90406eca2	ver-af1db78e	project-001	1	2	2	Page 2	Core collaboration 11:00 AM – 4:00 PM (all employees available)\nhours\nFlexible start 9:00 AM – 10:30 AM, provided 8 working hours\nwindow are completed\nMinimum daily 8 hours for a full day; 4 hours for a half day\nhours\nSupport/NOC roles Shift-based: General (9:30–18:30), Evening\n(14:00–23:00), Night (22:00–07:00)\nShift employees receive a shift allowance (see Employee Benefits\nHandbook, NXR-HR-POL-004).\n3. Attendance Recording\n• Office: Swipe in and out using the access card at the entry\nturnstile. Biometric is used as backup.\n• Work from home: Check in and out on PeopleHub Mobile (geo-\ntag optional) and keep Teams status "Available" during core\nhours.\n• Client site: Mark "On Duty" in PeopleHub with client name and\napproval from manager.\n• Attendance is locked on the 25th of each month for payroll.\nCorrections must be raised by the 24th.\n• Missed swipes may be regularised up to 3 times per month with\nmanager approval.\n4. Late Arrival Rules\nArrival Time Treatment\nUp to 10:30 AM (flexible Normal, if 8 hours completed\nwindow)\n10:31 – 11:00 AM "Late mark" (grace limit: 3 per month)	a3561fa7798bbae4524a6d4c7d9711225af5ead44239ead00350ed93e6a06cc4	gemini-embedding-2	indexed	2026-10-08 15:06:54.162423
77bcac93-cfbb-4c10-a5cd-b3816f2efa25	tenant-001	doc-03b90406eca2	ver-af1db78e	project-001	2	3	3	Page 3	After 11:00 AM without prior Half-day leave deducted\napproval\n4th late mark in a month 0.5 day CL deducted\n8 or more late marks in a Manager counselling; written warning\nquarter if repeated\nExample: Priya reaches the Pune office at 10:50 AM on three different\ndays in October. These are three late marks, so no deduction. On a\nfourth day she arrives at 10:45 AM, so 0.5 day CL is deducted.\nApproved exceptions: documented medical appointments, public\ntransport disruption declared by city authorities, and approved client-site\ntravel.\n5. Absence Handling\nSituation Action\nPlanned absence Apply leave in advance (see Leave\nPolicy, NXR-HR-POL-001)\nUnplanned absence Inform manager by 10:00 AM via phone\nor Teams; apply leave within 2 working\ndays of return\nAbsent without information Marked LOP; verbal warning\nfor 1 day\nAbsent without information Notice to show cause issued by HR\nfor 3 or more consecutive\ndays\nAbsent without information Treated as absconding; employment\nfor 7 or more consecutive may be terminated after notice to the\ndays registered address\n6. Overtime and Compensatory Off	ac499a23f714e4d7a24b5776c3cf04abbe6e7a1f2ba5fbbac52f3d045a9ec377	gemini-embedding-2	indexed	2026-10-08 15:06:55.054152
7c35b351-bdcf-450d-be6b-f998834706f0	tenant-001	doc-03b90406eca2	ver-af1db78e	project-001	3	4	4	Page 4	• Overtime is not paid for managerial and exempt roles (L4 and\nabove).\n• For L1–L3 and shift support staff, work beyond standard hours is\neligible only when pre-approved in writing by the manager.\n• Weekend or holiday work of 4+ hours earns 0.5 day comp-off; 8+\nhours earns 1 day comp-off.\n• Production support (on-call) rotation: ₹1,500 per weekend day on\ncall and ₹600 per weekday night of on-call.\n• Maximum overtime: 50 hours per quarter, in line with state shops-\nand-establishments rules.\nExample: During the Project Meridian go-live on Saturday 14 June,\nKaran (QA Engineer, L2) works 9 hours with manager approval. He\nreceives 1 comp-off, to be used within 60 days.\n7. Roles and Responsibilities\n• Employees: Record attendance accurately, communicate\nabsences early.\n• Managers: Review the team's attendance dashboard weekly and\napprove regularisations within 2 working days.\n• HR Operations: Run the monthly attendance report and share\nexceptions with HR Business Partners by the 27th.\n8. Violations\nFalsifying attendance (proxy swipes, edited logs) is a serious offence\nunder the Code of Employee Conduct and may lead to termination.	f2e9a601d1d36ac8c0dabe4b7f9bd50be31c8cd35c4e54ce0beaede7894089fd	gemini-embedding-2	indexed	2026-10-08 15:06:55.886873
e780ab15-e3bc-489c-8de9-0a6150408760	tenant-001	doc-9a4395663625	ver-d591d0f2	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Data Management Procedure\nDocument NXR-HR-PRC-014\nID\nVersion 2.1\nEffective 1 April 2026\nDate\nOwner HR Operations with Data Protection Officer (Neeraj\nBhatt)\nApplies To All HR staff, managers and anyone handling\nemployee data\n1. Purpose\nTo describe how Nexora creates, stores, uses, updates, retains and\ndisposes of employee records, and how privacy is protected in line with\nthe Digital Personal Data Protection Act, 2023 and applicable labour\nlaws.\n2. Employee Records\nThe official record of each employee is held in PeopleHub (system of\nrecord) and a secured digital folder.	bf1a024fc42b36287cebf1eaba2f38af5a4c2a04b0b9713f1854c3d274dafd47	gemini-embedding-2	indexed	2026-10-08 15:07:01.194484
ab976207-f7a3-4c08-ba2c-ee88525ebc8c	tenant-001	doc-9a4395663625	ver-d591d0f2	project-001	1	2	2	Page 2	Record Type Contents Storage\nPersonal Name, address, contact, PeopleHub\nemergency contact, ID proofs, (encrypted)\nphoto\nEmployment Offer letter, contract, role, PeopleHub + HR\nlevel, department, manager, SharePoint\njoining and confirmation dates\nPayroll and Salary, tax declarations, PF/ Payroll system,\nstatutory UAN, bank details, gratuity access-restricted\nnomination\nPerformance Goals, ratings, feedback, PIP, PeopleHub –\npromotions Talent module\nAttendance and Swipe logs, leave balances, PeopleHub\nleave WFH records\nMedical and Insurance enrolment, claim Benefits vault;\ninsurance details, sick leave certificates held only by HR\nBenefits\nDisciplinary and Show-cause notices, Restricted HR\ngrievance investigation reports folder\nExit Resignation, F&F, relieving PeopleHub + HR\nletter, exit interview SharePoint\nOnly data needed for a specific business or legal purpose is collected\n(data minimisation). Employees are informed of the purpose through\nthe Employee Privacy Notice, signed at joining.\n3. Data Access and Authorisation\nRole Access Level\nEmployee Own record (view; edit contact, bank and nominee\ndetails)	2d936e059596b371d28957d20b3cd8d87c7b4cec7decdc225c759c17c7bb2cd9	gemini-embedding-2	indexed	2026-10-08 15:07:01.839304
f9086d1f-a0f7-46fb-8469-1b9c8b92dbe6	tenant-001	doc-9a4395663625	ver-d591d0f2	project-001	2	3	3	Page 3	Reporting Team's attendance, leave, performance and\nManager goals; no medical, bank or salary details\nHR Business Records of assigned departments (no payroll\nPartner details unless needed)\nHR Operations / Full access to employment and payroll data for\nPayroll processing\nFinance and Payroll and expense data on request\nAudit\nLegal and Case-specific records with written justification\nCompliance\nIT Admin System administration only; no content access\nwithout ticket approval\nLeadership Aggregated reports; individual data only when\nrequired for decisions (CEO/Head of HR approval)\n• Access is role-based, reviewed every quarter by HR and the\nInformation Security Office.\n• Access logs for sensitive records are retained for 12 months.\n• Sharing employee data with third parties (insurers, BGV agencies,\nauditors, payroll vendors, clients) requires a signed data-\nprocessing agreement or consent.\n• Client requests for staff details (for example, for background\nchecks on Atlas team members) are shared only with employee\nconsent and limited to what the contract requires.\n4. Updating Records\n• Employees update personal details in PeopleHub under My\nProfile; changes to name, marital status or bank account need\nsupporting documents verified by HR within 5 working days.\n• HR updates job-related changes (promotion, transfer, increment)\non the effective date.\n• Annual data-verification drive in April: each employee confirms\ntheir details.	3ca43bef70e591309363e79b055897bbce10abeaaf5ec69aea696bbb547c0983	gemini-embedding-2	indexed	2026-10-08 15:07:02.697961
c69cdba7-8a23-4df6-85c0-b142c884fbdb	tenant-001	doc-0a51cdb40625	ver-2870bb6f	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Benefits Handbook\nDocument ID NXR-HR-HBK-004\nVersion 4.0\nEffective Date 1 April 2026\nOwner Compensation & Benefits (Anita Rao)\nInsurance Group health: Medisure TPA; Life and accident:\nPartners Suraksha Life\n1. Introduction\nThis handbook summarises the benefits available to Nexora employees\nand how to claim them. Detailed terms are in the insurer policy\ndocuments available on PeopleHub under Benefits.\n2. Health Insurance\nFeature Details\nPlan type Group Mediclaim, family floater\nSum insured ₹5,00,000 per family per year\nCovered members Employee, spouse, up to 2 children	430e2bc0fbe704950fbf909188f6ad6ed44a9a2522fbf953c271393bb5d32a12	gemini-embedding-2	indexed	2026-10-08 15:06:57.097698
d59bac82-2121-4136-861f-386e3a1b2760	tenant-001	doc-0a51cdb40625	ver-2870bb6f	project-001	1	2	2	Page 2	Parents / parents- Optional top-up of ₹3,00,000; premium paid by\nin-law employee through payroll\nCoverage starts Day one of employment\nMaternity Up to ₹75,000 (normal) / ₹1,00,000 (C-section);\nno waiting period\nPre-existing Covered from day one\nconditions\nPre/post 30 days before and 60 days after\nhospitalisation\nCashless network 6,500+ hospitals, including Ruby Hall (Pune),\nManipal (Bengaluru) and Apollo (Hyderabad)\nAnnual health Free for employee and spouse at partner labs\ncheck-up\n3. Life and Accident Insurance\nBenefit Cover\nGroup Term Life 3 × annual fixed pay, capped at\n₹75,00,000\nGroup Personal Accident ₹30,00,000 (death or permanent total\ndisability)\nCritical illness (employee ₹3,00,000 lump sum\nonly)\nNominees are updated in PeopleHub. Employees should review\nnominees after marriage, birth of a child or other life events.\n4. Allowances and Reimbursements	ce28c54170559151c14b056826eff4a9b71446d555ee8ac8674b283537b68100	gemini-embedding-2	indexed	2026-10-08 15:06:57.706771
81410c4c-c21f-4271-b78d-8231418b87de	tenant-001	doc-0a51cdb40625	ver-2870bb6f	project-001	2	3	3	Page 3	Allowance Amount Frequency Notes\nMeal card ₹2,200 per Monthly Pre-tax meal\nmonth vouchers on\nPluxee-type card\nWellness ₹12,000 Annual Gym, yoga,\ncounselling, fitness\napps; bills required\nInternet ₹1,500 per Monthly See WFH Policy\n(hybrid) month\nMobile and ₹800 per month Monthly Managers L4 and\ndata above\nNight shift ₹300 per night Per shift Support staff on\n22:00–07:00 shift\nRelocation Up to ₹50,000 One-time Needs 12-month\n(new joiners) service commitment\nReferral ₹25,000 (L1–L3) Per hire Paid after referred\nbonus / ₹50,000 (L4+) hire completes 6\nmonths\nLong service 5 years: ₹25,000 One-time\naward gift voucher; 10\nyears: ₹75,000\n5. Retirement and Statutory Benefits\n• Provident Fund (PF): 12% of basic pay by employee and 12% by\nemployer.\n• Gratuity: Payable after 5 years of continuous service as per the\nPayment of Gratuity Act, 1972.\n• ESI: Applicable only where wages fall under the statutory ceiling.\n• Professional tax and TDS: Deducted as per applicable law.\nInvestment declarations are due by 15 January.	45a095c960052162c5dc3737e3b1132c652e91c913f1f63126b8550a3d66cd8a	gemini-embedding-2	indexed	2026-10-08 15:06:58.331436
4af7d708-6c64-4e88-b01b-cfd15c4c1e52	tenant-001	doc-0a51cdb40625	ver-2870bb6f	project-001	3	4	4	Page 4	6. Employee Discounts and Perks\nPartner Offer\nCult-style fitness network 25% off membership\nCloud and software partners Free personal cloud credits up to\n(internal tie-ups) $100 per year\nOnline learning marketplace 30% off personal subscriptions\nCab partner 15% off airport rides\nCompany merchandise store 20% employee discount\nQuarterly team events, annual offsite and festival gifts are managed by\nthe Culture Committee.\n7. Eligibility Summary\nGroup Health & Allowances Referral Long\nLife Bonus Service\nConfirmed Yes Yes Yes Yes\nemployee\nProbationer Yes Yes (except After No\nrelocation until confirmation\nconfirmation)\nIntern Accident Meal card only No No\ncover\nonly\nContractor / No No No No\nconsultant\n8. How to Claim	27f40dd4b7d7ce2ebe3a005184c663e792cebb4965baa5c47187e002635428a9	gemini-embedding-2	indexed	2026-10-08 15:06:59.156983
6aa9ac42-f97d-4b2b-a6a4-152563dbd361	tenant-001	doc-0a51cdb40625	ver-2870bb6f	project-001	4	5	5	Page 5	Cashless hospitalisation\n1. Show the Medisure e-card at the network hospital desk.\n2. The hospital sends a pre-authorisation request to the TPA\n(approval usually within 4 hours).\n3. Pay only non-covered items at discharge.\nReimbursement claims (health or allowances)\n1. Submit the claim in PeopleHub → Claims with original bills,\ndischarge summary or invoices.\n2. Deadline: within 30 days of discharge or expense (45 days for\ninsurance claims).\n3. HR reviews within 5 working days; payment is made with the next\nsalary cycle.\nExample: Rohan (Senior Engineer, Pune) spends ₹18,400 on a gym\nmembership in July. He uploads the invoice by 31 July, receives\n₹12,000 under the annual wellness allowance and pays the remaining\n₹6,400 himself.\n9. Contacts\nBenefits helpdesk: benefits@nexora-tech.example. TPA helpline:\n1800-000-1234 (24 × 7).	026f1d982c2fd7267d64f90cf5d803880e53197ce9ae11af26250aed3388514c	gemini-embedding-2	indexed	2026-10-08 15:06:59.842861
4d510371-efdf-4841-a62d-c7187e7f0774	tenant-001	doc-becad9a82359	ver-408e9912	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Grievance Procedure\nDocument ID NXR-HR-PRC-010\nVersion 2.0\nEffective Date 1 April 2026\nOwner Employee Relations (Sunita\nJoshi)\nApplies To All employees and interns\n1. Purpose\nTo give every employee a safe, fair and timely way to raise work-related\nconcerns and have them resolved without fear of retaliation.\n2. What Is a Grievance?\nA grievance is a formal complaint about a work-related matter, for\nexample:\n• Unfair treatment, discrimination or favouritism\n• Workload or work-allocation concerns\n• Rating, increment or promotion decisions (after the feedback\nmeeting)	3f2e07a6895e237899c632f9d764b9714231196731f18e61c8a415650e61f713	gemini-embedding-2	indexed	2026-10-08 15:07:05.234311
e0d02367-7222-414c-9114-27217cd32a20	tenant-001	doc-becad9a82359	ver-408e9912	project-001	1	2	2	Page 2	• Pay, leave or attendance errors\n• Manager or peer behaviour, bullying\n• Working conditions, facilities or safety\nOut of scope: Sexual harassment complaints (go to the Internal\nCommittee under the Code of Conduct), whistleblower or fraud reports\n(go to ethics@nexora-tech.example), and legal disputes or notices.\n3. How to Submit a Grievance\nChannel Details\nPeopleHub Help → Raise a Grievance (preferred; creates a ticket\nnumber)\nEmail grievance@nexora-tech.example\nIn person HR Business Partner or Employee Relations team\nAnonymous Ethics hotline (+91-20-5550-0177) or web form; limited\nfollow-up is possible\nEmployees are encouraged to first discuss minor issues informally with\ntheir manager or HR Business Partner. A formal grievance should\ninclude a clear description, dates, people involved, supporting\ndocuments and the resolution sought.\n4. Escalation Levels and Timelines\nLevel Handler Acknowledgement Resolution\nTarget\nLevel 0: Reporting Same day 3 working\nInformal Manager / HRBP days\nLevel 1: HR Business 1 working day 7 working\nFormal Partner days	7edf6966842a4d0bb1714b9fada209d22c5fae94ca867205c13c8db9ad07e9ee	gemini-embedding-2	indexed	2026-10-08 15:07:06.08804
8a795b0a-eccd-4c45-873b-87c4946c2657	tenant-001	doc-9a4395663625	ver-d591d0f2	project-001	3	4	4	Page 4	• Corrections of errors are logged with date, reason and approver\n(audit trail).\n5. Retention Schedule\nRecord Retention Period After\nRetention\nRecruitment records of 12 months Delete\nunsuccessful candidates\nEmployment contract, 8 years after exit Secure\npersonnel file deletion\nPayroll, PF, gratuity and 8 years after exit (or as Archive then\ntax records per statute, whichever is delete\nlonger)\nAttendance and leave 5 years Delete\nPerformance records 5 years after exit Delete\nDisciplinary and 5 years after closure Delete\ngrievance files (longer if litigation\npending)\nPOSH inquiry records 5 years Secure\ndeletion\nMedical and insurance 3 years after exit Delete\nrecords\nCCTV and access logs 90 days Auto-\noverwrite\nLegal hold: Records required for an ongoing investigation or legal\nproceeding are retained until the Legal team lifts the hold.\n6. Privacy and Employee Rights	f74533585b8290d7a02a608ea2781505ccc842a53cec870b2e3e3cdf98be541e	gemini-embedding-2	indexed	2026-10-08 15:07:03.280876
a888bd48-7b62-4b65-b070-73a7362bed0a	tenant-001	doc-9a4395663625	ver-d591d0f2	project-001	4	5	5	Page 5	Employees can: access their data, request correction, request erasure of\ndata no longer needed, withdraw consent for optional uses (for example,\nbirthday announcements, photos), nominate a person to exercise rights\nin case of death or incapacity, and raise a privacy complaint with the\nData Protection Officer at dpo@nexora-tech.example. Requests are\nanswered within 15 working days.\n7. Security and Breach Handling\nEmployee data is encrypted at rest and in transit; printing and local\ndownloads of restricted data are blocked. Any suspected data breach\nmust be reported to the Security Operations Centre immediately (see\nNXR-IT-GDL-008). The DPO assesses and informs affected employees\nand the Data Protection Board of India as required by law.\n8. Disposal\nPaper records are shredded, and digital records are deleted with\ncertified wiping. Disposal is logged and approved by HR Operations and\nthe DPO.\nExample: Pallavi leaves Nexora on 31 July 2026. Her personnel and\npayroll records will be kept until 31 July 2034. Her performance and\nattendance files will be deleted on 31 July 2031. When she asks in\nSeptember 2026 for her old payslips, HR provides them after verifying\nher identity, within 5 working days.	fa600deff8fa8c9eb31627653d38cf343109fc407636623907345886d3a093ff	gemini-embedding-2	indexed	2026-10-08 15:07:03.932368
b95a2586-a3c9-47ff-990d-d5528676bf4f	tenant-001	doc-b02ac5215dad	ver-3d7fd15f	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Leave Policy\nDocument NXR-HR-POL-001\nID\nVersion 3.2\nEffective 1 April 2026\nDate\nOwner Head of HR (Meera Iyer)\nApplies To All confirmed employees and probationers at Pune,\nBengaluru and Hyderabad offices\nLeave Year 1 April – 31 March\n1. Purpose\nThis policy sets out the types of leave available at Nexora, who is\neligible, how balances are calculated, how leave is approved, and how\nunused leave is carried forward. Leave is recorded in PeopleHub, the\ncompany HRMS.\n2. Types of Leave and Entitlement	2a64f9bb558187b71947f8d42c34e86f236822443e8730d442be268ab9e5005b	gemini-embedding-2	indexed	2026-10-08 15:07:09.042898
78794d35-1709-425f-bc89-154b03e6b1fb	tenant-001	doc-b02ac5215dad	ver-3d7fd15f	project-001	1	2	2	Page 2	Leave Type Entitlement Eligibility Notes\n(per year)\nCasual Leave 8 days From date of Max 3\n(CL) joining consecutive\ndays\nSick Leave 8 days From date of Medical\n(SL) joining certificate\nneeded for\nmore than 2\nconsecutive\ndays\nEarned Leave 18 days After 3 months Planned leave;\n(EL) of service; notice required\naccrues 1.5\ndays/month\nMaternity 26 weeks (first Female As per Maternity\nLeave two children) employees Benefit Act,\nwith 80+ days 1961\nof service\nPaternity 10 working Confirmed To be taken\nLeave days male within 6 months\nemployees of birth\nMarriage 5 working days Confirmed Invitation or\nLeave employees, certificate on\nfirst marriage request\nBereavement 5 working days Immediate Applicable from\nLeave family (parent, day one\nspouse, child,\nsibling)\nCompensatory 1 day per All employees Must be used\nOff approved within 60 days\nweekend/\nholiday work\nday	04454685312e310f0bf4e615cdab00c8a2d1562d95913759713e6a4cc9492ccc	gemini-embedding-2	indexed	2026-10-08 15:07:09.63385
d607c47a-d2e8-4f71-bb82-c13e0d648449	tenant-001	doc-b02ac5215dad	ver-3d7fd15f	project-001	2	3	3	Page 3	Loss of Pay As required When balance Deducted per\n(LOP) is exhausted day from\nmonthly salary\nJoining mid-year: CL and SL are credited pro-rata (rounded up to the\nnearest half day).\n3. Leave Balance\n• EL accrues on the last day of each month. CL and SL are credited\non 1 April.\n• Balances are visible in PeopleHub under My Leave → Balance.\n• Weekends and declared company holidays falling inside a leave\nperiod are not counted, except when they fall between two\nperiods of sick leave exceeding 5 days.\nExample: Arjun (Senior Engineer, Project Atlas) joins on 1 July 2026.\nHis CL and SL for the year are pro-rata: 8 × 9/12 = 6 days each. EL\nstarts accruing after he completes 3 months (from 1 October).\n4. Approval Process\nLeave Apply In Advance Approver\nDuration\n1–2 days 2 working days Reporting Manager\n3–5 days 7 working days Reporting Manager\n6–10 days 15 working days Reporting Manager\n+ Project/Delivery\nHead\nMore than 10 30 working days Delivery Head +\ndays HR Business\nPartner	978f58f3a913241d0446c2b876b3e9196e520a76d6d4ad7b5b35b8bc6c2debb6	gemini-embedding-2	indexed	2026-10-08 15:07:10.245382
cb4e4333-2083-4a57-b88a-f161f7993900	tenant-001	doc-b02ac5215dad	ver-3d7fd15f	project-001	3	4	4	Page 4	Sick leave Inform manager before 10:00 Reporting Manager\n(unplanned) AM same day; apply within 2\nworking days of return\nSteps\n1. Employee applies in PeopleHub and selects leave type and dates.\n2. Manager approves or rejects within 2 working days. Unactioned\nrequests escalate automatically to the manager's manager.\n3. For client-facing roles, the employee names a backup colleague\nand updates the project calendar (for example, the Atlas sprint\nplanner).\n4. HR reviews leave exceeding 10 days and any pattern of leave\nadjacent to weekends or holidays.\nManagers may defer (not deny without reason) leave during critical\nrelease windows such as production go-live, giving an alternate date\nwithin 2 weeks.\n5. Carry-Forward and Encashment\nLeave Carry Forward Encashment\nType\nEarned Up to 30 days total Balance above 30 is encashed at\nLeave balance basic pay / 26 per day at year end\nCasual Not allowed; lapses No\nLeave on 31 March\nSick Up to 8 days No\nLeave accumulate (cap\n16)\nComp-off Lapses after 60 No\ndays\nOn separation, unused EL is encashed in the full-and-final settlement.\nNegative EL balance is recovered.	bab5d5a49327e0135f28572d3a1a33a5483bfee9746782c5b5f4c1ab712e5670	gemini-embedding-2	indexed	2026-10-08 15:07:10.897194
74aac8c5-8efe-43db-a91d-924b81980dd9	tenant-001	doc-a453aa814971	ver-58e8bc5d	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nHR Department Annual Report: FY 2025–26\nReporting period: 1 April 2025 – 31 March 2026 | Prepared by: Meera\nIyer, Head of HR | Date: 24 April 2026\nDocument ID NXR-HR-RPT-015\nVersion 1.0\nAudience Executive Leadership Team and Board\n1. Executive Summary\nFY 2025–26 was a year of steady growth. Headcount grew from 372 to\n420 (+13%) as we staffed Project Atlas (payments platform), Project\nMeridian (banking reconciliation) and Project Beacon (internal HRMS\nrebuild). We hired 110 people, kept voluntary attrition at 12.9%,\ndelivered about 37 learning hours per employee, and rolled out the\nhybrid work model and PeopleHub 2.0.\n2. Employee Statistics (as of 31 March 2026)\nDepartment Headcount Share\nEngineering 232 55.2%\nQA 56 13.3%	a96f4882ec263ae95b61a5f4fc843f01c6703f91029ccd6217a22fb1d02caf11	gemini-embedding-2	indexed	2026-10-08 15:07:22.266769
af115f9b-ecd3-4716-ad40-49864626e926	tenant-001	doc-becad9a82359	ver-408e9912	project-001	2	3	3	Page 3	Level 2: Head of HR 2 working days 15 working\nEscalation (Meera Iyer) with days\nDepartment\nHead\nLevel 3: Committee of 3 3 working days 30 working\nGrievance (HR Head, Legal days\nCommittee rep, senior leader\nfrom another\ndepartment)\nAn employee may escalate if no response is received within the stated\ntime or if unsatisfied with the outcome (within 7 working days of\nreceiving the decision). If the grievance involves the reporting manager\nor HRBP, the employee may go directly to Level 2.\n5. Investigation Process\n1. Intake: HR logs the case and assigns an investigator who has no\nconflict of interest.\n2. Acknowledgement: The employee receives a confirmation with a\nticket number and expected timeline.\n3. Fact-finding: Investigator interviews the complainant, the\nrespondent and witnesses, and reviews records such as emails,\nattendance and performance data.\n4. Fairness: Both sides get a chance to present their version.\nInterviews are documented and signed.\n5. Findings: A written report with findings and recommendations is\nprepared.\n6. Decision and communication: Outcome shared with the\nemployee in a meeting and by email.\n7. Closure: HR follows up after 30 days to confirm the resolution is\nworking.\n6. Possible Resolutions	5e36b9100e56a18c709d5eca74bb87d6d2df513f35c7ab5c247cb07c79d2867e	gemini-embedding-2	indexed	2026-10-08 15:07:06.906656
744cfd00-e6fc-4169-8f21-1f600d4bdd76	tenant-001	doc-becad9a82359	ver-408e9912	project-001	3	4	4	Page 4	Clarification or mediation; correction of records (leave, pay, rating);\ncoaching or training for the manager; change of reporting line or team;\ndisciplinary action under the Code of Employee Conduct; process\nchanges. If the complaint is found unsubstantiated, no action is taken\nagainst the complainant unless it was made with malicious intent.\n7. Confidentiality and Non-Retaliation\n• Information is shared only with people who need it for the\ninvestigation.\n• Retaliation, including threats, unfair ratings, or exclusion, is a\nserious violation. Report retaliation directly to the Head of HR.\n8. Records and Metrics\nCases are retained for 5 years. HR reports quarterly to the leadership\nteam on grievance count, categories, average resolution time and repeat\nissues, without personal details.\nExample: Dev (Engineer, Project Atlas) raises a grievance on 4 August\nthat his on-call rota exceeded the agreed one week in three. His HRBP\nacknowledges the next day, reviews the rota with the delivery manager,\nand by 10 August the rota is corrected and Dev receives two comp-off\ndays. The case is closed after a 30-day check-in.	568c17a3ba07d11efb776069373469b219c547c50d4167d838522f9d508ad83e	gemini-embedding-2	indexed	2026-10-08 15:07:07.717614
0575e74e-a557-4404-bf27-2d77ff6e98e6	tenant-001	doc-b02ac5215dad	ver-3d7fd15f	project-001	4	5	5	Page 5	6. Other Rules\n• Probation: Employees on probation may use CL, SL and\nstatutory leave. EL is available only after confirmation or with HR\napproval.\n• Public holidays: The company declares 11 holidays per year (list\npublished each January). Employees get 2 floating holidays.\n• Extended medical leave: Beyond available balance, up to 90\ndays of unpaid medical leave may be approved by HR on\nsubmission of medical documents.\n• Misuse: Falsified medical certificates or leave on false grounds\nare handled under the Code of Employee Conduct (NXR-HR-\nPOL-009).\n7. Roles and Responsibilities\n• Employee: Apply on time, hand over work, keep contact details\ncurrent.\n• Manager: Approve or reject within 2 working days and plan team\ncoverage.\n• HR Operations: Maintain the leave calendar, run year-end carry-\nforward on 1 April, resolve balance disputes within 5 working\ndays.\n8. Revision History\nVersion Date Change\n3.0 1 April Added 2 floating holidays\n2024\n3.1 1 April Paternity leave increased from 7 to 10 days\n2025	6d3e5a155e0c044d8ec4c6420f6cf0a3c869e8ca4ab632199ae9e29c24917795	gemini-embedding-2	indexed	2026-10-08 15:07:11.689658
99978b8b-3eaa-4a90-bd38-061dc005c4fc	tenant-001	doc-b02ac5215dad	ver-3d7fd15f	project-001	5	6	6	Page 6	3.2 1 April EL carry-forward cap raised from 24 to 30\n2026 days	99e5cee82921f562ad1ac0dff0d8fc4cf47ba96f55daf2f3da4d5b1bbc3fbef8	gemini-embedding-2	indexed	2026-10-08 15:07:12.271125
17bb1e98-9ca3-446d-86a4-1ce3cdfcb972	tenant-001	doc-37cea547ae24	ver-871cf972	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Offboarding Procedure\nDocument NXR-HR-PRC-007\nID\nVersion 2.2\nEffective 1 April 2026\nDate\nOwner HR Operations (Rahul Deshmukh)\nApplies To All employees leaving through resignation,\ntermination, retirement or end of contract\n1. Purpose\nTo ensure a respectful, orderly and secure exit, with proper knowledge\ntransfer, return of assets, deactivation of access and timely full-and-final\n(F&F) settlement.\n2. Resignation Process\n1. Employee submits resignation in PeopleHub → Separation and\nemails the reporting manager.\n2. Manager acknowledges within 2 working days and discusses\nreasons and retention options.	1b5af4f15e0ba385441126741567f2ece2a2d0e043b8004413490e5d4daf5bc7	gemini-embedding-2	indexed	2026-10-08 15:07:13.9146
01bdc177-1689-4d91-944a-f627e98e202d	tenant-001	doc-37cea547ae24	ver-871cf972	project-001	1	2	2	Page 2	3. HR Business Partner schedules an exit conversation within 5\nworking days.\n4. HR issues the resignation acceptance letter confirming the last\nworking day (LWD).\n5. Employee follows the exit checklist in Section 6.\n3. Notice Period\nCategory Notice Period\nProbationers 30 days\nConfirmed employees, L1–L3 60 days\nConfirmed employees, L4 and above 90 days\nContract and interns As per contract\n• Notice buy-out: Possible with Department Head and HR\napproval. The employee pays basic + fixed allowances for the\nshortfall days. Buy-out is not available during critical project\nphases or if a client contract requires named resources.\n• Leave during notice: Leave is not allowed in the last 15 days of\nnotice, except for medical emergencies. Unused earned leave is\nencashed in F&F.\n• Early release: Considered case by case if knowledge transfer is\ncomplete and the manager approves.\n• Garden leave or immediate release: The company may relieve\nan employee early with pay in lieu of notice.\n4. Knowledge Transfer (KT)\nA KT plan must be agreed within 5 working days of resignation\nacceptance.\nItem Details	798ab8ef4ffe45cfb6780fbdbbab8f66df525c99aa33ee728415c670c992e543	gemini-embedding-2	indexed	2026-10-08 15:07:14.693544
e8f73eb8-c6d6-41e1-8126-00c5409d2fe6	tenant-001	doc-37cea547ae24	ver-871cf972	project-001	2	3	3	Page 3	KT owner Resigning employee; supervised by the manager\nDuration Minimum 2 weeks for L1–L3; 4 weeks for L4+\nContent Code and architecture walkthroughs, runbooks,\nopen tickets, client contacts, credentials handover\n(via vault)\nDocumentation Confluence pages updated; recorded sessions\nstored in the project SharePoint\nSign-off Successor and manager confirm completion in\nPeopleHub\nExample: Rohit (Lead, Project Atlas) resigns on 1 August with a 90-day\nnotice. He documents the payment gateway integration, runs four\nrecorded sessions for his successor Meena, and completes sign-off by\n15 October, two weeks before his LWD of 30 October.\n5. Asset Return and Account Deactivation\nAsset / Access Owner Timeline\nLaptop, charger, IT Return on LWD; data wipe\naccessories after backup review\nAccess card, ID card, Admin LWD\nparking pass\nCorporate credit card, SIM, Finance / LWD\nmobile IT\nEmail, Teams, Jira, IT Disabled at 6:30 PM on\nGitHub, cloud consoles Security LWD\nVPN and MFA tokens IT Disabled on LWD\nSecurity\nShared passwords and Project Rotated within 24 hours\nAPI keys Lead	663cf8c970fa4985c1e27677ef9192446a332c93cc1fdeb2ca89bf9ded025332	gemini-embedding-2	indexed	2026-10-08 15:07:15.309499
cb23fdbf-3f26-4bf0-942c-12cea9a9a96b	tenant-001	doc-37cea547ae24	ver-871cf972	project-001	3	4	4	Page 4	Email forwarding to IT 30 days, then deleted\nmanager\nMissing or damaged assets are charged at depreciated value and\nrecovered from F&F.\n6. Exit Checklist\n# Task Owner\n1 Submit resignation in PeopleHub Employee\n2 Complete KT and get sign-off Employee /\nManager\n3 Clear pending expense claims Employee /\nFinance\n4 Return assets Employee / IT /\nAdmin\n5 Complete exit interview and feedback form Employee / HR\n6 Obtain no-dues clearance from IT, Admin, All departments\nFinance, Library, Project\n7 Receive relieving letter and experience letter HR\n6A. Full-and-Final Settlement\n• Includes salary till LWD, EL encashment, gratuity (if eligible),\nbonus pro-rata where applicable, less recoveries (notice shortfall,\nloans, assets, training bond).\n• Paid within 30 days of LWD, subject to clearance of all dues.\n• Form 16 is issued by 30 June of the following year. PF transfer is\nsupported through the UAN portal.	814f11dd530c5f7b2d989621087d997e9b900da09d48ea836834f8f03a52f09c	gemini-embedding-2	indexed	2026-10-08 15:07:15.935934
110d0906-2a06-47a8-a5c0-896fc9d52fc1	tenant-001	doc-37cea547ae24	ver-871cf972	project-001	4	5	5	Page 5	7. Exit Interview\nConducted by an HR Business Partner (not the reporting manager).\nResponses are confidential and shared only as aggregated themes with\nleadership.\n8. Rehire\nEmployees who leave in good standing with rating 3 or above are\neligible for rehire after a 6-month gap. Past service is not carried over\nunless approved by the Head of HR.	f86725cce78d4fad23f49fc01a2d7cce7e4141824bce00a7e2b281cbd52612c5	gemini-embedding-2	indexed	2026-10-08 15:07:16.745541
878b3e6f-a3c6-4a2e-ae89-314ec9521320	tenant-001	doc-5e4f6cd7d179	ver-76575f76	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Onboarding Procedure\nDocument NXR-HR-PRC-006\nID\nVersion 2.3\nEffective 1 April 2026\nDate\nOwner HR Operations (Rahul Deshmukh)\nApplies To All new joiners (full-time employees, interns, fixed-\nterm staff)\n1. Purpose\nTo give every new joiner a smooth, compliant and welcoming start, and\nto ensure accounts, equipment, training and documents are ready by\nDay 1.\n2. Roles and Responsibilities\nRole Responsibility\nHR Operations Offer paperwork, document verification, induction\nschedule	869b1f7b99a771fb8d6ed9d37c221e601529bcd2b719d3d3ecb8c135504e39e0	gemini-embedding-2	indexed	2026-10-08 15:07:18.113188
cdefdbcb-8ba9-4685-b8b6-35b49d35a37b	tenant-001	doc-5e4f6cd7d179	ver-76575f76	project-001	1	2	2	Page 2	Hiring Manager Buddy assignment, 30-60-90 day plan, project\nintroduction\nIT Service Desk Laptop, accounts, access, security briefing\nAdmin & Access card, desk, parking, ID card\nFacilities\nFinance & Salary setup, PF/UAN, bank details\nPayroll\nOnboarding Day-to-day guide for the first 30 days\nBuddy\n3. Pre-Joining (Offer Accepted to Day -1)\nTimeline Action Owner\nOffer Welcome email with joining checklist HR\nacceptance\nT-10 days Background verification (BGV) initiated HR\nthrough third-party agency\nT-7 days Laptop and accessories requested on Manager\nServiceDesk\nT-5 days Buddy assigned; team informed Manager\nT-3 days Email ID and Teams account created IT\n(not yet activated)\nT-1 day Reminder call; confirm reporting time and HR\nlocation\n4. Document Verification\nOriginals must be shown on Day 1; copies are retained.	df84c8a9b6595201384b4269be33d53526d8e7f8be798b6c33b18cb9b79ba24d	gemini-embedding-2	indexed	2026-10-08 15:07:18.703501
c10b72c1-3a0b-42fa-855f-c97ebd64098e	tenant-001	doc-5e4f6cd7d179	ver-76575f76	project-001	2	3	3	Page 3	Category Documents\nIdentity Aadhaar, PAN (mandatory), passport (if available)\nAddress Aadhaar or utility bill / rental agreement\nEducation Degree and mark sheets (highest qualification\nmandatory)\nEmployment Relieving letter, last 3 payslips, experience letters from\nprevious employers\nFinancial Cancelled cheque or bank statement, UAN number\nOther 4 passport photographs, medical fitness (for night-shift\nroles)\nIf documents are pending, HR may allow up to 7 working days to\nsubmit, with manager approval. Joining may be withdrawn if BGV finds\nmaterial discrepancies.\n5. Account and Access Creation\nSystem Provided Ready By\nBy\nCompany email and Microsoft IT Day 1, 10:00 AM\nTeams\nPeopleHub (HRMS) HR Day 1\nVPN and multi-factor IT Day 1\nauthentication\nJira, Confluence, GitHub Project Day 2\nEnterprise Admin\nProject-specific environments (for Project Day 3, after\nexample, Atlas staging) Lead security training\nServiceDesk IT Day 1\nAccess follows the least privilege principle. Production access is	632360447a2ef22a637e043d6a3d59225fb3de42a9718e1057c58886434b3881	gemini-embedding-2	indexed	2026-10-08 15:07:19.487539
4b9ab862-9e85-42ac-9530-8c7859cd1aa2	tenant-001	doc-5e4f6cd7d179	ver-76575f76	project-001	3	4	4	Page 4	granted only after 30 days and manager approval.\n6. Induction and Training\nDay Session\nDay 1 Welcome, company overview, HR policies, benefits\nwalkthrough\nDay 2 Information security and Remote Work Security training\n(mandatory, assessed)\nDay 3 POSH and Code of Conduct awareness (e-learning)\nWeek 1 Meet team, project overview, architecture walkthrough\nWeek Role-based technical onboarding with buddy\n2–4\n7. First-Week Checklist\n# Item Done\n1 Submit original documents to HR\n☐\n2 Receive laptop, ID card and access card\n☐\n3 Log in to email, Teams, PeopleHub and set up MFA\n☐\n4 Complete security and compliance training (score 80%\n☐\nor more)\n5 Sign confidentiality agreement and policy\n☐\nacknowledgements\n6 Enrol in group health insurance and add nominees\n☐\n7 Meet manager and agree 30-60-90 day plan\n☐\n8 Meet buddy and join team stand-up\n☐	db54bc7fa4cc0051f8aa9e40744550cebbd4571a04e8f466445f01580e95fdab	gemini-embedding-2	indexed	2026-10-08 15:07:20.060827
026980af-8e9c-4789-b016-2bd7c5f02c31	tenant-001	doc-5e4f6cd7d179	ver-76575f76	project-001	4	5	5	Page 5	9 Get access to the project repositories and Jira board\n☐\n10 Complete first-week feedback survey\n☐\n8. Probation and Follow-Ups\n• HR check-in on Day 7, Day 30 and Day 90.\n• Probation period is 6 months for L1–L3 and 3 months for L4+,\nsubject to the confirmation process in the Performance Review\nGuidelines.\nExample: Ishita Sharma joins as Engineer (L2) on Project Beacon on\nMonday 6 July 2026. HR verifies her documents by 10:30 AM, IT hands\nover her laptop, and she completes security training on Tuesday. By\nFriday she has merged her first pull request with help from her buddy,\nVikram.	f9e449675d64af9c8c1f5d365170e1ffd10570361a640dad522569d490a9e4d2	gemini-embedding-2	indexed	2026-10-08 15:07:20.686192
9b1dcd3e-cd26-4faf-8390-be2116f88f71	tenant-001	doc-e9cdba142890	ver-42aa2f8a	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nPerformance Review Guidelines\nDocument NXR-HR-GDL-005\nID\nVersion 3.0\nEffective 1 April 2026\nDate\nOwner Talent Management (Kavita Menon)\nApplies To All confirmed employees; probationers follow the\nprobation review in Section 9\n1. Purpose\nTo provide a fair, transparent and consistent method for evaluating\nperformance, giving feedback and linking outcomes to increments,\nbonuses and promotions.\n2. Review Cycle\nPhase Period Activity\nGoal setting 1 April – 30 Employee and manager agree 4–\nApril 6 goals in PeopleHub	45c3c336fe5117736ca9f12470bb4db7a1a78f2dde1554115de23a621a130b14	gemini-embedding-2	indexed	2026-10-08 15:07:28.010579
2d2248bf-a78a-45f5-880c-e1467a575f08	tenant-001	doc-e9cdba142890	ver-42aa2f8a	project-001	1	2	2	Page 2	Mid-year check-in 1 – 31 Progress review, goal\nOctober adjustment, development plan\nQuarterly 1:1s July, Informal feedback conversation\nJanuary\nSelf-assessment 1 – 10 Employee rates own performance\nMarch with evidence\nManager 11 – 20 Manager rates and writes\nassessment March comments\nCalibration 21 – 31 Department and HR calibration\nMarch sessions\nRating 1 – 10 April One-to-one feedback meeting\ncommunication\nIncrements and Effective 1 Paid with May salary\nbonus May\nThe appraisal year is April to March, aligned to the financial year.\n3. Evaluation Criteria\nEach employee is assessed on what was delivered (70%) and how it\nwas delivered (30%).\nComponent Weight Examples\nGoal achievement 50% Delivery against Atlas sprint\ncommitments, defect rates, client\nCSAT, revenue targets\nQuality and 20% Code review quality, documentation,\nownership on-call reliability\nCollaboration and 15% Teamwork across squads,\ncommunication stakeholder updates, mentoring\nNexora values 15% Integrity, Customer First,\nContinuous Learning, Ownership	f9039537dafac5898009186c8b36e625edf3d8f3b2c548d7ca34c075e6829a58	gemini-embedding-2	indexed	2026-10-08 15:07:28.61057
e33ff153-e278-4b11-a338-87287bdbdf02	tenant-001	doc-e9cdba142890	ver-42aa2f8a	project-001	2	3	3	Page 3	Managers (L4 and above) are also assessed on team engagement,\nattrition and talent development.\n4. Rating Scale\nRating Label Description Guidance\nDistribution\n5 Outstanding Exceptional impact About 5–8%\nbeyond role\n4 Exceeds Consistently above About 20–25%\nExpectations expectations\n3 Meets Fully meets role About 55–60%\nExpectations requirements\n2 Needs Partially meets; About 10–12%\nImprovement improvement plan\nneeded\n1 Unsatisfactory Does not meet Below 3%\nrequirements\nDistribution is a guide, not a forced curve. Departments with strong\nresults can justify a different spread during calibration.\n5. Manager Responsibilities\n• Set clear, measurable goals (SMART) within 30 days of the cycle\nstart.\n• Hold at least one structured 1:1 per month and document key\npoints in PeopleHub.\n• Collect peer feedback from at least 3 colleagues for each team\nmember (360-degree input for L3 and above).\n• Avoid recency bias by reviewing the full-year record, including\nsprint reports, client feedback and incident logs.	ccc7b203eec45467038bb24296ba9e6dd7ed96a0814ba4c2d9ae13010989e736	gemini-embedding-2	indexed	2026-10-08 15:07:29.495984
9b077c83-92ca-42a3-aa32-6eaddfa5cfd6	tenant-001	doc-a453aa814971	ver-58e8bc5d	project-001	1	2	2	Page 2	Data & AI 38 9.0%\nProduct & Design 34 8.1%\nSales & Pre-sales 22 5.2%\nIT & Admin 18 4.3%\nFinance 11 2.6%\nHR 9 2.1%\nTotal 420 100%\nMetric Value\nLocation split Pune 246 (58.6%), Bengaluru 118 (28.1%),\nHyderabad 56 (13.3%)\nWomen employees 160 (38.1%); 29% of leadership roles (L4 and\nabove)\nAverage age 31.4 years\nAverage tenure 3.2 years\nFully remote 14\nemployees\n3. Hiring\nMetric FY 2024–25 FY 2025–26\nTotal hires 94 110\nExperienced hires / Campus hires 78 / 16 86 / 24\nEmployee referrals 31% 38%\nAverage time to hire 41 days 36 days\nOffer acceptance rate 78% 84%\nCost per hire ₹62,000 ₹54,000	7263cbbe91362a95a00eca7224371a870da4f227cfc3071a2f6fd32b4988ae8d	gemini-embedding-2	indexed	2026-10-08 15:07:22.866316
6f9eb089-446d-4a5d-a0ce-7a1291233d21	tenant-001	doc-a453aa814971	ver-58e8bc5d	project-001	2	3	3	Page 3	Hires by department: Engineering 68, QA 14, Data & AI 10, Product &\nDesign 9, Sales & Pre-sales 5, HR/Finance/Admin 4 (total 110).\n4. Attrition\nMetric FY 2024– FY 2025–26\n25\nTotal exits 56 62\nVoluntary exits 47 51\nInvoluntary exits 9 11\nOverall attrition (annualised) 16.1% 15.7%\nVoluntary attrition 13.5% 12.9%\nAttrition in first year of service 24% of exits 21% of exits\nOverall attrition is calculated as exits ÷ average headcount (62 ÷ 396).\nTop reasons for leaving (exit interviews): higher compensation\nelsewhere (34%), career growth (27%), relocation or higher studies\n(16%), work-life balance (11%), others (12%). Engineering had the\nhighest attrition at 17.4%; HR and Finance the lowest.\n5. Training and Development\nMetric Result\nTotal learning hours 14,800 (average 37 hours per employee)\nLearning budget spent ₹1.12 crore (84% utilisation)\nCertifications completed 143 (AWS 46, Azure 31, Security 18,\nISTQB 22, others 26)\nNexora Academy Cloud 3 batches; 72 graduates\nBootcamp	d70a0307935dc4924eaac782159d1f75c44cede01cd255b269e0103a63a0ee5b	gemini-embedding-2	indexed	2026-10-08 15:07:23.682398
c28ee212-4800-4118-92cb-0d76469859c2	tenant-001	doc-a453aa814971	ver-58e8bc5d	project-001	3	4	4	Page 4	Mandatory training 100% (security, POSH, Code of\ncompletion Conduct)\nAverage programme 4.4 / 5\nfeedback\nMentoring pairs 96\n6. Performance Trends (FY 2025–26 Cycle)\nRating Share of Employees FY 2024–25\n5 – Outstanding 6% 5%\n4 – Exceeds 24% 22%\n3 – Meets 56% 58%\n2 – Needs Improvement 12% 13%\n1 – Unsatisfactory 2% 2%\n• Average increment: 8.4%; promotions: 38 employees (9.0%)\nacross April and October cycles.\n• 9 employees were placed on PIP; 5 completed successfully, 3\nexited and 1 is ongoing.\n• Mid-year check-in completion: 96%; goal-setting completion by 30\nApril: 98%.\n7. Employee Engagement and Well-being\nMetric FY 2024–25 FY 2025–26\nEngagement survey score 72% 78%\nParticipation 81% 90%\neNPS +18 +27	fd8f3f9d548ce6d7c8c57b19572983fb353e0a9efc623ccda90744223b7179fa	gemini-embedding-2	indexed	2026-10-08 15:07:24.504101
728dcb0e-94a8-4ff2-b339-d0c0bf5222ef	tenant-001	doc-a453aa814971	ver-58e8bc5d	project-001	4	5	5	Page 5	Grievances received 27 21\nAverage grievance resolution time 12 days 8 days\nPOSH complaints 1 0\nEmployee Assistance Programme (EAP) counselling was used by 58\nemployees. Wellness allowance utilisation: 71%.\n8. Major HR Initiatives in FY 2025–26\n1. Hybrid work model (3 office, 2 WFH) launched in June with\ninternet allowance of ₹1,500 per month.\n2. PeopleHub 2.0 went live in August, bringing leave, attendance,\nclaims, performance and grievances onto one platform.\n3. Revised benefits: Health cover raised from ₹4 lakh to ₹5 lakh;\nparental top-up option added.\n4. Leave policy update: Paternity leave increased to 10 days, EL\ncarry-forward cap increased to 30 days.\n5. Career framework: Published level guidelines (L1–L7) and dual\ncareer tracks in October.\n6. Women in Tech programme: Mentoring and returnship for 18\nparticipants.\n7. DPDP readiness: Employee privacy notice, retention schedule\nand data-access review completed.\n9. HR Budget\nItem Budget (₹ Actual (₹\nlakh) lakh)\nRecruitment 70 59\nTraining and development 133 112\nEngagement and events 40 43	f1a15f33ff38f0b4911b04e38cd96d4f3d051e12552d23c2de5955690d1ff594	gemini-embedding-2	indexed	2026-10-08 15:07:25.359314
676868af-8e86-42c8-8311-a48b7b6a19ac	tenant-001	doc-a453aa814971	ver-58e8bc5d	project-001	5	6	6	Page 6	HR technology (PeopleHub, tools) 55 58\nWellness and benefits 30 27\nadministration\nTotal 328 299\n10. Priorities for FY 2026–27\nPriority Target\nReduce voluntary Below 11.5%\nattrition\nHiring 90 net hires with 40% referral share\nLearning 40 hours per employee; 150 certifications\nEngagement Survey score 80%; eNPS +30\nDiversity 33% women in leadership roles (L4+) by\nMarch 2027\nCompensation Complete market benchmarking for\nengineering roles by September 2026\nAutomation Launch employee self-service chatbot for HR\nqueries on PeopleHub\nSuccession Identify successors for all L5 and above roles\n11. Conclusion\nNexora's people strategy supported business growth while improving\nhiring speed, engagement and learning. The focus for next year is\nretention in engineering, stronger career paths and further digitisation of\nHR services.\nAppendix: Detailed data tables are available from HR Analytics (hr-	9fbf85b54115cf5582aa8f6c686c1c3f3a6b6d0ef423420a4f7209020be50032	gemini-embedding-2	indexed	2026-10-08 15:07:26.170208
aba9657b-0049-4d8f-9831-2bc9ea783f15	tenant-001	doc-a453aa814971	ver-58e8bc5d	project-001	6	7	7	Page 7	analytics@nexora-tech.example).	5ba6df08cc90e3a9ede5f66ee0cf209035b437b47e3b29b624009f8d9d3ad189	gemini-embedding-2	indexed	2026-10-08 15:07:26.753961
80d1506f-6e6d-4762-9de7-4ef2e6a35f47	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	0	1	1	Page 1	Practical_3_24CS099\nEnvironment Setup & Local Data Loading\nimport os\nimport warnings\nimport numpy as np\nimport pandas as pd\nimport matplotlib.pyplot as plt\nimport seaborn as sns\nfrom sklearn.model_selection import train_test_split\nfrom sklearn.preprocessing import StandardScaler\nfrom sklearn.linear_model import LogisticRegression\nfrom sklearn.metrics import (\naccuracy_score, precision_score, recall_score, f1_score,\nroc_auc_score, confusion_matrix, classification_report\n)\nfrom imblearn.over_sampling import SMOTE\nwarnings.filterwarnings('ignore')\nplt.style.use("ggplot")\n# Load local dataset directly\ndf = pd.read_csv("diabetes.csv")\nprint("First 5 records:")\nprint(df.head())\nFirst 5 records:\nPregnancies Glucose BloodPressure SkinThickness Insulin\nBMI \\\n0 6 148 72 35 0 33.6\n1 1 85 66 29 0 26.6\n2 8 183 64 0 0 23.3\n3 1 89 66 23 94 28.1\n4 0 137 40 35 168 43.1\nDiabetesPedigreeFunction Age Outcome\n0 0.627 50 1\n1 0.351 31 0\n2 0.672 32 1	7f077548e30749fc7831af82dac93fd0ed1a585a3202ee630d6a65a7a1ce5486	gemini-embedding-2	indexed	2026-10-08 15:07:36.489199
ec536719-9b2c-4430-a9db-99b797755b72	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	1	2	2	Page 2	3 0.167 21 0\n4 2.288 33 1\nDataset Dimensions\nprint("rows:", df.shape[0])\nprint("columns:", df.shape[1])\nprint("Shape:", df.shape)\nrows: 768\ncolumns: 9\nShape: (768, 9)\nSummary Statistics\ndf.describe(include="all")\n{"summary":"{\\n \\"name\\": \\"df\\",\\n \\"rows\\": 8,\\n \\"fields\\": [\\n\n{\\n \\"column\\": \\"Pregnancies\\",\\n \\"properties\\": {\\n\n\\"dtype\\": \\"number\\",\\n \\"std\\": 269.85223453356366,\\n\n\\"min\\": 0.0,\\n \\"max\\": 768.0,\\n \\"num_unique_values\\":\n8,\\n \\"samples\\": [\\n 3.8450520833333335,\\n\n3.0,\\n 768.0\\n ],\\n \\"semantic_type\\": \\"\\",\\n\n\\"description\\": \\"\\"\\n }\\n },\\n {\\n \\"column\\":\n\\"Glucose\\",\\n \\"properties\\": {\\n \\"dtype\\": \\"number\\",\\\nn \\"std\\": 243.73802348295857,\\n \\"min\\": 0.0,\\n\n\\"max\\": 768.0,\\n \\"num_unique_values\\": 8,\\n\n\\"samples\\": [\\n 120.89453125,\\n 117.0,\\n\n768.0\\n ],\\n \\"semantic_type\\": \\"\\",\\n\n\\"description\\": \\"\\"\\n }\\n },\\n {\\n \\"column\\":\n\\"BloodPressure\\",\\n \\"properties\\": {\\n \\"dtype\\":\n\\"number\\",\\n \\"std\\": 252.85250535810619,\\n \\"min\\":\n0.0,\\n \\"max\\": 768.0,\\n \\"num_unique_values\\": 8,\\n\n\\"samples\\": [\\n 69.10546875,\\n 72.0,\\n\n768.0\\n ],\\n \\"semantic_type\\": \\"\\",\\n\n\\"description\\": \\"\\"\\n }\\n },\\n {\\n \\"column\\":\n\\"SkinThickness\\",\\n \\"properties\\": {\\n \\"dtype\\":\n\\"number\\",\\n \\"std\\": 263.7684730531098,\\n \\"min\\":\n0.0,\\n \\"max\\": 768.0,\\n \\"num_unique_values\\": 7,\\n\n\\"samples\\": [\\n 768.0,\\n 20.536458333333332,\\n\n32.0\\n ],\\n \\"semantic_type\\": \\"\\",\\n\n\\"description\\": \\"\\"\\n }\\n },\\n {\\n \\"column\\":\n\\"Insulin\\",\\n \\"properties\\": {\\n \\"dtype\\": \\"number\\",\\\nn \\"std\\": 350.26059167945886,\\n \\"min\\": 0.0,\\n\n\\"max\\": 846.0,\\n \\"num_unique_values\\": 7,\\n\n\\"samples\\": [\\n 768.0,\\n 79.79947916666667,\\n\n127.25\\n ],\\n \\"semantic_type\\": \\"\\",\\n\n\\"description\\": \\"\\"\\n }\\n },\\n {\\n \\"column\\":\n\\"BMI\\",\\n \\"properties\\": {\\n \\"dtype\\": \\"number\\",\\n	34272b1f4fc00916a929b3a8c902ccadd64183401c160206f4c83b9f6f39db33	gemini-embedding-2	indexed	2026-10-08 15:07:37.299614
e31e735a-6fcf-4d94-9f61-afa23bb1bb39	tenant-001	doc-e9cdba142890	ver-42aa2f8a	project-001	3	4	4	Page 4	• Communicate ratings in a face-to-face or video meeting with\nspecific examples.\n• Complete assessments by the deadline; late submissions are\nreported to the Department Head.\n6. Employee Responsibilities\n• Keep goals updated and record achievements with links (Jira\nepics, pull requests, client emails).\n• Request feedback proactively and complete the self-assessment\nhonestly.\n• Raise concerns about a rating through the Grievance Procedure\nwithin 15 days of the rating meeting.\n7. Impact on Compensation and Promotion\nRating Typical Annual Promotion Eligibility\nIncrement Bonus (% of\nRange target)\n5 12–18% 130% Fast-track nomination\n4 8–12% 110% Eligible\n3 5–8% 100% Eligible after tenure\ncriteria\n2 0–3% 50% Not eligible;\nimprovement plan\n1 0% 0% Not eligible;\nperformance\nimprovement plan (PIP)\nRanges are indicative and depend on company performance and budget\napproved by the Board.	38e9896c606843f777ed36c05ee317950d3e4d36799e4462d4174b3b6fa62d43	gemini-embedding-2	indexed	2026-10-08 15:07:30.368436
8b8dc033-fcb1-4289-a514-ad004e083791	tenant-001	doc-e9cdba142890	ver-42aa2f8a	project-001	4	5	5	Page 5	8. Performance Improvement Plan (PIP)\nEmployees rated 1, or rated 2 twice in a row, may be placed on a 60–90\nday PIP with documented targets, weekly check-ins and HR visibility.\nOutcomes: successful completion, extension (once, up to 30 days) or\nseparation.\n9. Probation Review\nNew joiners have reviews at 30, 60 and 90 days (180 days for L4+).\nConfirmation is by HR letter after a "Meets" or better review.\nExample: In FY 2025–26, Sneha (Senior Engineer, Project Meridian)\ndelivered the payment reconciliation module two sprints early, mentored\ntwo juniors and received strong client feedback. Her manager rated her\n4. She received a 10% increment effective 1 May 2026 and was\nnominated for promotion to Lead in the October cycle.	50c807d3a2116039324364301f26bebbbb8feed3d11caaa634e8fabb57e69f88	gemini-embedding-2	indexed	2026-10-08 15:07:31.075569
81ff41db-d39a-43dc-9488-7cc2571aac6c	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	2	3	3	Page 3	\\"std\\": 262.05117817552093,\\n \\"min\\": 0.0,\\n \\"max\\":\n768.0,\\n \\"num_unique_values\\": 8,\\n \\"samples\\": [\\n\n31.992578124999998,\\n 32.0,\\n 768.0\\n ],\\n\n\\"semantic_type\\": \\"\\",\\n \\"description\\": \\"\\"\\n }\\\nn },\\n {\\n \\"column\\": \\"DiabetesPedigreeFunction\\",\\n\n\\"properties\\": {\\n \\"dtype\\": \\"number\\",\\n \\"std\\":\n271.3005221658502,\\n \\"min\\": 0.078,\\n \\"max\\": 768.0,\\n\n\\"num_unique_values\\": 8,\\n \\"samples\\": [\\n\n0.47187630208333325,\\n 0.3725,\\n 768.0\\n ],\\n\n\\"semantic_type\\": \\"\\",\\n \\"description\\": \\"\\"\\n }\\\nn },\\n {\\n \\"column\\": \\"Age\\",\\n \\"properties\\": {\\n\n\\"dtype\\": \\"number\\",\\n \\"std\\": 260.1941178528413,\\n\n\\"min\\": 11.76023154067868,\\n \\"max\\": 768.0,\\n\n\\"num_unique_values\\": 8,\\n \\"samples\\": [\\n\n33.240885416666664,\\n 29.0,\\n 768.0\\n ],\\n\n\\"semantic_type\\": \\"\\",\\n \\"description\\": \\"\\"\\n }\\\nn },\\n {\\n \\"column\\": \\"Outcome\\",\\n \\"properties\\":\n{\\n \\"dtype\\": \\"number\\",\\n \\"std\\":\n271.3865920388932,\\n \\"min\\": 0.0,\\n \\"max\\": 768.0,\\n\n\\"num_unique_values\\": 5,\\n \\"samples\\": [\\n\n0.3489583333333333,\\n 1.0,\\n 0.4769513772427971\\n\n],\\n \\"semantic_type\\": \\"\\",\\n \\"description\\": \\"\\"\\n\n}\\n }\\n ]\\n}","type":"dataframe"}\nData Types & Column Classification\nprint("Data Types:\\n", df.dtypes)\ncategorical = df.select_dtypes(include="object").columns\nnumerical = df.select_dtypes(include=['int64', 'float64']).columns\nprint("\\nCategorical columns:", list(categorical))\nprint("Numerical columns:", list(numerical))\nData Types:\nPregnancies int64\nGlucose int64\nBloodPressure int64\nSkinThickness int64\nInsulin int64\nBMI float64\nDiabetesPedigreeFunction float64\nAge int64\nOutcome int64\ndtype: object\nCategorical columns: []\nNumerical columns: ['Pregnancies', 'Glucose', 'BloodPressure',\n'SkinThickness', 'Insulin', 'BMI', 'DiabetesPedigreeFunction', 'Age',\n'Outcome']	4b59aa3f2f0649636fd90a34abb430832f3d6fb842c7f331cd4e22c43ca63659	gemini-embedding-2	indexed	2026-10-08 15:07:37.953195
bd6a7306-7970-4cd8-81e1-63268f4f91d1	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	3	4	4	Page 4	Missing Values & Uniqueness Inspection\nprint("Null values count:\\n", df.isnull().sum())\nprint("\\nEmpty string values count:\\n", (df == " ").sum())\nprint("\\nDuplicate records count:", df.duplicated().sum())\nprint("\\nUnique values per column:\\n", df.nunique())\nNull values count:\nPregnancies 0\nGlucose 0\nBloodPressure 0\nSkinThickness 0\nInsulin 0\nBMI 0\nDiabetesPedigreeFunction 0\nAge 0\nOutcome 0\ndtype: int64\nEmpty string values count:\nPregnancies 0\nGlucose 0\nBloodPressure 0\nSkinThickness 0\nInsulin 0\nBMI 0\nDiabetesPedigreeFunction 0\nAge 0\nOutcome 0\ndtype: int64\nDuplicate records count: 0\nUnique values per column:\nPregnancies 17\nGlucose 136\nBloodPressure 47\nSkinThickness 51\nInsulin 186\nBMI 248\nDiabetesPedigreeFunction 517\nAge 52\nOutcome 2\ndtype: int64\nHead & Tail Check\nprint("Head:")\nprint(df.head())	f377746866761cda062490bf0546eecd11c78b61dd0b1e2e3802e0eabffdf574	gemini-embedding-2	indexed	2026-10-08 15:07:38.792628
5ac948ff-6cc6-442b-a696-25e240a55ff8	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	4	5	5	Page 5	print("Tail:")\nprint(df.tail())\nHead:\nPregnancies Glucose BloodPressure SkinThickness Insulin\nBMI \\\n0 6 148 72 35 0 33.6\n1 1 85 66 29 0 26.6\n2 8 183 64 0 0 23.3\n3 1 89 66 23 94 28.1\n4 0 137 40 35 168 43.1\nDiabetesPedigreeFunction Age Outcome\n0 0.627 50 1\n1 0.351 31 0\n2 0.672 32 1\n3 0.167 21 0\n4 2.288 33 1\nTail:\nPregnancies Glucose BloodPressure SkinThickness Insulin BMI\n\\\n763 10 101 76 48 180 32.9\n764 2 122 70 27 0 36.8\n765 5 121 72 23 112 26.2\n766 1 126 60 0 0 30.1\n767 1 93 70 31 0 30.4\nDiabetesPedigreeFunction Age Outcome\n763 0.171 63 0\n764 0.340 27 0\n765 0.245 30 0\n766 0.349 47 1\n767 0.315 23 0\nDataset Information Overview\ndf.info()\n<class 'pandas.core.frame.DataFrame'>\nRangeIndex: 768 entries, 0 to 767	bad7d5c9cdbe5280b05ef4cde685d1192b267a07d3bdadce3a742008433b3a6c	gemini-embedding-2	indexed	2026-10-08 15:07:39.389147
4e6016b6-5017-46e4-acca-f661ef707c75	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	5	6	6	Page 6	Data columns (total 9 columns):\n# Column Non-Null Count Dtype\n--- ------ -------------- -----\n0 Pregnancies 768 non-null int64\n1 Glucose 768 non-null int64\n2 BloodPressure 768 non-null int64\n3 SkinThickness 768 non-null int64\n4 Insulin 768 non-null int64\n5 BMI 768 non-null float64\n6 DiabetesPedigreeFunction 768 non-null float64\n7 Age 768 non-null int64\n8 Outcome 768 non-null int64\ndtypes: float64(2), int64(7)\nmemory usage: 54.1 KB\nFeature Correlation Heatmap & Target Association\ncorr = df.corr()\nplt.figure(figsize=(8, 6))\nplt.imshow(corr, cmap='coolwarm', interpolation='nearest')\nplt.colorbar()\nplt.xticks(range(len(corr.columns)), corr.columns, rotation=90)\nplt.yticks(range(len(corr.columns)), corr.columns)\nplt.title("Correlation Matrix")\nplt.show()\nprint("Correlation with Outcome:")\nprint(corr["Outcome"].sort_values(ascending=False))	6995c90b16d8b8cb0ff510c9da3b83205ead88a5e637ae3b055d646ceddae9d2	gemini-embedding-2	indexed	2026-10-08 15:07:40.192278
a97ec1ba-48d7-4c92-bdd1-e2ebb0db67b0	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	6	7	7	Page 7	Correlation with Outcome:\nOutcome 1.000000\nGlucose 0.466581\nBMI 0.292695\nAge 0.238356\nPregnancies 0.221898\nDiabetesPedigreeFunction 0.173844\nInsulin 0.130548\nSkinThickness 0.074752\nBloodPressure 0.065068\nName: Outcome, dtype: float64\nFeature Distributions & Class Balance Visualizations	d94feaf9d90f12e731684b7b85ddb5204d05f6469d0025a6ffb203fcb29bb5ee	gemini-embedding-2	indexed	2026-10-08 15:07:41.159638
b6fea489-b636-4373-b67f-a65bce5965c0	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	7	8	8	Page 8	# Feature Boxplots\ndf.plot(kind='box', figsize=(12, 6))\nplt.title("Boxplot of All Features")\nplt.xticks(rotation=45)\nplt.grid(True)\nplt.show()\n# Target Class Distribution\ncounts = df["Outcome"].value_counts()\nplt.figure(figsize=(5, 4))\nplt.bar(["Non-Diabetic", "Diabetic"], counts)\nplt.title("Count of Diabetic and Non-Diabetic Patients")\nplt.xlabel("Outcome")\nplt.ylabel("Number of Patients")\nplt.show()	274cd7e4042a68400fa5d279f0543fd5686199dd5223991c5cd8b677c283986a	gemini-embedding-2	indexed	2026-10-08 15:07:41.926662
0c43a785-a7d0-4911-9c54-1cd11f7d87a1	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	8	9	9	Page 9	Zero-Value Inspection & Invalid Zero Replacement\ncolumns_with_zero = ['Glucose', 'BloodPressure', 'SkinThickness',\n'Insulin', 'BMI']\nprint("Number of 0 values before replacement:\\n")\nfor col in columns_with_zero:\nprint(f"{col}: {(df[col] == 0).sum()}")\n# Replace 0s with NaN for biologically invalid zero measurements\ndf[columns_with_zero] = df[columns_with_zero].replace(0, np.nan)\nprint("\\nNumber of NaN values after replacing 0s:")\nprint(df.isnull().sum())\nNumber of 0 values before replacement:\nGlucose: 5\nBloodPressure: 35\nSkinThickness: 227\nInsulin: 374\nBMI: 11\nNumber of NaN values after replacing 0s:\nPregnancies 0\nGlucose 5\nBloodPressure 35	4fddff73a097ba2ae077300c84c51e1b12dea59b478ae4e3e52b6aba346be328	gemini-embedding-2	indexed	2026-10-08 15:07:42.49118
6cca5e0e-0925-463d-83b9-fa74dcc32bfa	tenant-001	doc-eb33be1c8687	ver-e891bb59	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nPromotion and Career Growth Guidelines\nDocument ID NXR-HR-GDL-012\nVersion 2.1\nEffective Date 1 April 2026\nOwner Talent Management (Kavita Menon)\nApplies To All confirmed employees\n1. Purpose\nTo describe the career levels at Nexora, the criteria for promotion, and\nthe review process so that employees understand how to grow and\nmanagers can make fair decisions.\n2. Career Levels\nLevel Engineering Title Typical Scope\nExperience\nL1 Associate 0–2 years Works on defined tasks\nEngineer with guidance	06de234df96a572146ab9833c319dd485b2e1d37b254d29cb93dabe6c201eb26	gemini-embedding-2	indexed	2026-10-08 15:07:52.716352
7eba6383-1436-476f-b32a-1bba1aa89da0	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	9	10	10	Page 10	SkinThickness 227\nInsulin 374\nBMI 11\nDiabetesPedigreeFunction 0\nAge 0\nOutcome 0\ndtype: int64\nMedian Imputation\nfor col in columns_with_zero:\ndf[col].fillna(df[col].median(), inplace=True)\nprint("\\nNumber of NaN values after median imputation:")\nprint(df.isnull().sum())\nNumber of NaN values after median imputation:\nPregnancies 0\nGlucose 0\nBloodPressure 0\nSkinThickness 0\nInsulin 0\nBMI 0\nDiabetesPedigreeFunction 0\nAge 0\nOutcome 0\ndtype: int64\nFeature Scaling & Dataset Splitting\nX = df.drop('Outcome', axis=1)\ny = df['Outcome']\nscaler = StandardScaler()\nX_scaled = scaler.fit_transform(X)\nX_scaled_df = pd.DataFrame(X_scaled, columns=X.columns)\n# Split into train and test sets with stratification\nX_train, X_test, y_train, y_test = train_test_split(\nX_scaled_df, y, test_size=0.2, random_state=42, stratify=y\n)\nprint("X_train shape:", X_train.shape)\nprint("X_test shape:", X_test.shape)\nprint("y_train shape:", y_train.shape)\nprint("y_test shape:", y_test.shape)\nprint("\\nClass distribution in training set:")	8c4079e426598bd47535a448bb1762f4e20e3cdca0f511bdb25fd4d0c8920578	gemini-embedding-2	indexed	2026-10-08 15:07:43.091203
17260e6d-4801-4e52-b3e6-51629f88f37d	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	10	11	11	Page 11	print(pd.Series(y_train).value_counts())\nprint("\\nClass distribution in test set:")\nprint(pd.Series(y_test).value_counts(normalize=True))\nX_train shape: (614, 8)\nX_test shape: (154, 8)\ny_train shape: (614,)\ny_test shape: (154,)\nClass distribution in training set:\nOutcome\n0 400\n1 214\nName: count, dtype: int64\nClass distribution in test set:\nOutcome\n0 0.649351\n1 0.350649\nName: proportion, dtype: float64\nVerify & Handle Residual Missing Values\n# Impute any residual NaNs within train/test sets if present\nX_train = X_train.fillna(X_train.median(numeric_only=True))\nX_test = X_test.fillna(X_test.median(numeric_only=True))\nprint("Missing values in X_train:", X_train.isnull().sum().sum())\nprint("Missing values in X_test:", X_test.isnull().sum().sum())\nMissing values in X_train: 0\nMissing values in X_test: 0\nBaseline Logistic Regression Model\nmodel_base = LogisticRegression(random_state=42)\nmodel_base.fit(X_train, y_train)\nprint("Baseline Logistic Regression Model trained successfully")\nBaseline Logistic Regression Model trained successfully\nBaseline Model Evaluation\ny_pred_base = model_base.predict(X_test)\ny_pred_proba_base = model_base.predict_proba(X_test)[:, 1]\nconf_matrix_base = confusion_matrix(y_test, y_pred_base)\nprint("Confusion Matrix (Baseline):")	521472e97e61287606d946e96cc6a0a97ad53908467baea6ba61aae90a28bbf0	gemini-embedding-2	indexed	2026-10-08 15:07:43.870097
37f6ad8b-1b8f-43a2-b620-979415f47a67	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	11	12	12	Page 12	print(conf_matrix_base)\nplt.figure(figsize=(6, 4))\nsns.heatmap(\nconf_matrix_base, annot=True, fmt="d", cmap="Blues",\nxticklabels=['Predicted Non-Diabetic', 'Predicted Diabetic'],\nyticklabels=['Actual Non-Diabetic', 'Actual Diabetic']\n)\nplt.title("Confusion Matrix (Baseline)")\nplt.show()\nacc_base = accuracy_score(y_test, y_pred_base)\nprec_base = precision_score(y_test, y_pred_base)\nrec_base = recall_score(y_test, y_pred_base)\nf1_base = f1_score(y_test, y_pred_base)\nroc_base = roc_auc_score(y_test, y_pred_proba_base)\nprint(f"Accuracy: {acc_base:.4f}")\nprint(f"Precision: {prec_base:.4f}")\nprint(f"Recall: {rec_base:.4f}")\nprint(f"F1 Score: {f1_base:.4f}")\nprint(f"ROC AUC Score: {roc_base:.4f}")\nConfusion Matrix (Baseline):\n[[81 19]\n[27 27]]	cf6d8a1c26b66810d3a65d3ae5ba00c84abb93523e0d3b420fc7e29735065454	gemini-embedding-2	indexed	2026-10-08 15:07:44.673345
0043ab43-380c-471e-a073-8de061b60f7b	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	12	13	13	Page 13	Accuracy: 0.7013\nPrecision: 0.5870\nRecall: 0.5000\nF1 Score: 0.5400\nROC AUC Score: 0.8128\nApply SMOTE & Train Resampled Model\nsmote = SMOTE(random_state=42)\nX_train_resampled, y_train_resampled = smote.fit_resample(X_train,\ny_train)\nprint("Class distribution after SMOTE:")\nprint(pd.Series(y_train_resampled).value_counts())\nmodel_resampled = LogisticRegression(random_state=42)\nmodel_resampled.fit(X_train_resampled, y_train_resampled)\nprint("\\nLogistic Regression Model (Resampled) trained successfully")\nClass distribution after SMOTE:\nOutcome\n0 400\n1 400\nName: count, dtype: int64\nLogistic Regression Model (Resampled) trained successfully\nResampled Model Evaluation\ny_pred_smote = model_resampled.predict(X_test)\ny_pred_proba_smote = model_resampled.predict_proba(X_test)[:, 1]\nconf_matrix_smote = confusion_matrix(y_test, y_pred_smote)\nprint("Confusion Matrix (SMOTE Model):")\nprint(conf_matrix_smote)\nplt.figure(figsize=(6, 4))\nsns.heatmap(\nconf_matrix_smote, annot=True, fmt="d", cmap="Greens",\nxticklabels=['Predicted Non-Diabetic', 'Predicted Diabetic'],\nyticklabels=['Actual Non-Diabetic', 'Actual Diabetic']\n)\nplt.title("Confusion Matrix (SMOTE Resampled Model)")\nplt.show()\nacc_smote = accuracy_score(y_test, y_pred_smote)\nprec_smote = precision_score(y_test, y_pred_smote)\nrec_smote = recall_score(y_test, y_pred_smote)	3566b345cb22fff6727bc773dbb6a11f10bd21fc44c122cbf24a2acf92a2f782	gemini-embedding-2	indexed	2026-10-08 15:07:45.489399
8eca2306-3b68-43f3-a80c-c461a1c38ad3	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	13	14	14	Page 14	f1_smote = f1_score(y_test, y_pred_smote)\nroc_smote = roc_auc_score(y_test, y_pred_proba_smote)\nprint(f"Accuracy: {acc_smote:.4f}")\nprint(f"Precision: {prec_smote:.4f}")\nprint(f"Recall: {rec_smote:.4f}")\nprint(f"F1 Score: {f1_smote:.4f}")\nprint(f"ROC AUC Score: {roc_smote:.4f}")\nConfusion Matrix (SMOTE Model):\n[[74 26]\n[17 37]]\nAccuracy: 0.7208\nPrecision: 0.5873\nRecall: 0.6852\nF1 Score: 0.6325\nROC AUC Score: 0.8109\nFeature Importance (Logistic Regression Coefficients)\nfeature_importance = pd.DataFrame({\n'Feature': X.columns,\n'Coefficient': model_resampled.coef_[0]\n}).sort_values(by='Coefficient', ascending=False)	d5bd2ab4363605e10d9ffb7033cc5c3e82bbbbe297d06a96321562b33a9d1730	gemini-embedding-2	indexed	2026-10-08 15:07:46.317163
a85d310c-3f87-4db1-95d1-a193a3185137	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	14	15	15	Page 15	print("\\nFeature Importance (Resampled Model):\\n")\nprint(feature_importance)\nplt.figure(figsize=(10, 6))\nsns.barplot(x='Coefficient', y='Feature', data=feature_importance,\npalette='viridis')\nplt.title('Logistic Regression Feature Coefficients (Resampled\nModel)')\nplt.xlabel('Coefficient Value')\nplt.ylabel('Feature')\nplt.show()\nFeature Importance (Resampled Model):\nFeature Coefficient\n1 Glucose 1.272081\n5 BMI 0.766550\n0 Pregnancies 0.293924\n6 DiabetesPedigreeFunction 0.251101\n7 Age 0.148011\n3 SkinThickness 0.062731\n2 BloodPressure -0.056352\n4 Insulin -0.120413\nPerformance Metrics Comparison (Before vs. After SMOTE)\ncomparison_data = {\n'Metric': ['Accuracy', 'Precision', 'Recall', 'F1 Score', 'ROC AUC	d821678a0033793207ae775e8841ac7d2dedd1692360cc65ca07adda37373f60	gemini-embedding-2	indexed	2026-10-08 15:07:47.105364
555d8a7c-944e-4136-b7bb-37e42bb6fc07	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	15	16	16	Page 16	Score'],\n'Before SMOTE': [acc_base, prec_base, rec_base, f1_base,\nroc_base],\n'After SMOTE': [acc_smote, prec_smote, rec_smote, f1_smote,\nroc_smote]\n}\ncomparison_df = pd.DataFrame(comparison_data)\nprint("Comparison of Model Metrics (Before vs. After SMOTE):")\nprint(comparison_df.round(4))\nComparison of Model Metrics (Before vs. After SMOTE):\nMetric Before SMOTE After SMOTE\n0 Accuracy 0.7013 0.7208\n1 Precision 0.5870 0.5873\n2 Recall 0.5000 0.6852\n3 F1 Score 0.5400 0.6325\n4 ROC AUC Score 0.8128 0.8109\nHigh-Risk Non-Diabetic Subgroup Analysis\n# Combine actual outcomes, predicted probabilities, and original\nfeatures\nresults_df = pd.DataFrame({\n'Actual_Outcome': y_test,\n'Predicted_Probability': y_pred_proba_smote\n}).reset_index(drop=True)\noriginal_X_test_df = pd.DataFrame(X_test,\ncolumns=X.columns).reset_index(drop=True)\nresults_df = pd.concat([results_df, original_X_test_df], axis=1)\n# Cases where actual outcome is non-diabetic (0) but predicted\nprobability > 0.5\nhigh_risk_non_diabetic = results_df[\n(results_df['Actual_Outcome'] == 0) &\n(results_df['Predicted_Probability'] > 0.5)\n]\nprint("\\nPatient records with high-risk probabilities despite being\nclassified as non-diabetic:")\nprint(high_risk_non_diabetic.head())\nprint("\\nSummary statistics for high-risk non-diabetic patients:")\nprint(high_risk_non_diabetic.describe())\nPatient records with high-risk probabilities despite being classified\nas non-diabetic:	360bba847df0b201abe5d44076be71995cada6b0298919ae6efe22eb026d9df3	gemini-embedding-2	indexed	2026-10-08 15:07:47.896507
6df331b4-a336-4ea9-ab7f-3a12d8583578	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	16	17	17	Page 17	Actual_Outcome Predicted_Probability Pregnancies Glucose \\\n0 0 0.737877 0.936914 1.227667\n9 0 0.932256 -1.141852 1.424916\n16 0 0.810598 1.827813 1.326292\n18 0 0.901781 -0.250952 2.279660\n24 0 0.688832 0.936914 0.109925\nBloodPressure SkinThickness Insulin BMI \\\n0 -0.693761 -0.012301 -0.181541 -0.735763\n9 0.298896 1.581234 1.324364 2.247921\n16 0.960667 -0.012301 -0.181541 -0.692100\n18 -0.362876 -1.605837 -0.123622 -0.226354\n24 1.126110 -0.012301 -0.181541 0.748802\nDiabetesPedigreeFunction Age\n0 -0.537208 0.575118\n9 -0.642912 -0.616111\n16 -0.875461 1.766346\n18 -0.522107 0.064591\n24 -0.507006 1.511083\nSummary statistics for high-risk non-diabetic patients:\nActual_Outcome Predicted_Probability Pregnancies\nGlucose \\\ncount 26.0 26.000000 26.000000 26.000000\nmean 0.0 0.742853 0.308715 0.782593\nstd 0.0 0.137609 1.161824 0.855868\nmin 0.0 0.506046 -1.141852 -0.613320\n25% 0.0 0.658336 -0.770643 0.151018\n50% 0.0 0.744164 0.046014 0.701671\n75% 0.0 0.836890 0.936914 1.301635\nmax 0.0 0.947908 2.718712 2.378284\nBloodPressure SkinThickness Insulin BMI \\\ncount 26.000000 26.000000 26.000000 26.000000\nmean 0.435704 0.442995 0.669875 0.677149\nstd 0.913970 1.090336 1.694375 1.047572\nmin -1.851862 -2.061133 -0.413219 -0.954082\n25% -0.156072 -0.012301 -0.181541 -0.153581\n50% 0.381617 0.329171 -0.181541 0.734247\n75% 1.105430 1.325130 0.504804 1.196354\nmax 1.870603 2.833298 6.247517 2.888322	54f244963ae73af17a18128e73f2f8c78b7e10f9ecec3de2895dfa3043ecffca	gemini-embedding-2	indexed	2026-10-08 15:07:48.741738
5d8a6809-c4c9-48b5-ac35-395f3892ec0a	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	17	18	18	Page 18	DiabetesPedigreeFunction Age\ncount 26.000000 26.000000\nmean -0.245418 0.146407\nstd 0.603682 1.084455\nmin -1.044587 -1.041549\n25% -0.682173 -0.616111\n50% -0.469255 -0.360847\n75% 0.227638 0.724021\nmax 1.305065 2.872487\nPrepared by 24CS099	5a9bf9fec5ecfd7bb4b0bf541b18d0dcc0875f51b6e1cd5e2280d9ccd192efc3	gemini-embedding-2	indexed	2026-10-08 15:07:49.595331
f69cbc69-4398-41d3-88ee-daeb5cb11be3	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	18	19	19	Page 19	CSUC301 – MACHINE LEARNING 24CS099-Hetvi Tank\nFaculty of Technology and Engineering\nChandubhai S. Patel Institute of Technology\nDepartment of Computer Science & Engineering\nDate: 08/08/2026\nPractical Performa\nAcademic Year : 2026-27 Semester : 5th\nCourse code : CSUC301 Course name : Machine Learning\nPractical- No. 3\nAim: Implement a linear regression:\nImplement a logistic regression:A healthcare organization aims to identify individuals\nwho are at high risk of developing diabetes using patient health measurements collected\nduring routine medical examinations. The organization requires a predictive system that\ncan estimate the likelihood of diabetes occurrence and support early intervention\nstrategies. Develop an solution capable of assessing risk, handling challenges in the\ndataset, and providing reliable decision support for healthcare professionals..\n• Questions and Answers :\n1. Which patient attributes appear to have the strongest influence on diabetes occurrence?\n→Based on the logistic regression coefficients, Glucose clearly emerges as the single strongest\npredictor of diabetes occurrence. It is followed closely by BMI, Pregnancies, and Diabetes\nPedigree Function, all of which display substantial positive influence on the target outcome.\nConversely, attributes like Skin Thickness and Blood Pressure show minimal to slightly\nnegative predictive weights. Overall, metabolic indicators related to blood sugar levels and\nbody mass index dominate the model's decision-making process.	74dbc7d55f8b28a27085da72db4c626cd22208168fcf09b0de61742cc834d4c9	gemini-embedding-2	indexed	2026-10-08 15:07:50.195149
e7a00a4a-347e-43a0-802e-5f9e46e0003f	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	19	20	20	Page 20	CSUC301 – MACHINE LEARNING 24CS099-Hetvi Tank\nIs the dataset balanced across outcome classes? What impact could class imbalance have\n2.\non prediction quality?\n→No, the dataset is noticeably imbalanced, with roughly 65% of individuals classified as non-\ndiabetic and only 35% as diabetic. Left unaddressed, this skew causes a machine learning\nmodel to favor the majority class, predicting "non-diabetic" more often to artificially inflate\noverall accuracy.\n→ Consequently, the model suffers from poor sensitivity, missing a high proportion of actual\ndiabetic patients. Oversampling techniques like SMOTE help balance training data to ensure\nthe minority class receives equal emphasis during learning.\nHow effectively can the developed solution distinguish diabetic and non-diabetic\n3.\npatients? Justify using appropriate evaluation measures [confusion matrix, accuracy,\nprecision, recall, F1-score]\n→After applying SMOTE, the developed logistic regression model demonstrates a moderate\nability to separate diabetic from non-diabetic cases. Across the test set, it achieves an overall\naccuracy of about 71–72%. Looking at the confusion matrix, it correctly identifies 74 true\nnegatives and 37 true positives, while producing 26 false positives and 17 false negatives. With\na precision of ~0.58, a recall of ~0.67, and an F1-score around 0.62, the solution shows strong\nminority-class recovery but still leaves room for reducing false alarms.\n4.\nWhich evaluation measures provide the most reliable assessment for this healthcare\nproblem?\n→In healthcare risk assessment, Recall (Sensitivity) and the F1-Score provide far more\nreliable metrics than simple accuracy. Accuracy can easily mask poor performance when\ndealing with imbalanced medical datasets. Recall is particularly critical because it directly\ncaptures the proportion of actual positive cases successfully detected by the system. Pairing it\nwith F1-Score ensures a balanced evaluation, holding the model accountable for both missing\nsick patients and generating excessive false alarms.\n5.\nWhich patient records receive high-risk probabilities despite being classified as non\ndiabetic, and what insights can be derived from such cases?\n→ Patients receiving high predicted probabilities despite being labeled non-diabetic (Actual\nOutcome = 0, Probability > 0.5) represent borderline or early-stage risk profiles. Although not\nyet officially diagnosed as diabetic, their summary statistics reveal elevated average values for\nkey features like Glucose and BMI compared to typical healthy individuals. These cases\nsuggest that while clinical labels are binary, diabetes risk operates on a continuous spectrum.\nIdentifying these high-risk non-diabetic individuals creates a valuable window for early\nlifestyle interventions before full disease onset.	fc9b5a1a86fb1fcf6699dac8d9788af72c974c45f5e7c68765f596191749a33b	gemini-embedding-2	indexed	2026-10-08 15:07:51.015663
89c068dc-57bc-4449-90b8-3878fdc067ed	tenant-001	doc-bd628377481b	ver-4355ff10	project-001	20	21	21	Page 21	CSUC301 – MACHINE LEARNING 24CS099-Hetvi Tank\nWhat are the consequences of false positives and false negatives in a healthcare setting?\n6.\n→ In a medical setting, false negatives carry severe clinical consequences because delayed\ndiagnoses allow disease progression, increasing long-term complication risks and treatment\ncosts. On the flip side, false positives trigger unnecessary patient anxiety, additional diagnostic\ntesting, and potential exposure to unneeded treatments. While both misclassifications impose\nburdens on healthcare infrastructure, false negatives are generally considered far more\ndangerous due to direct threats to patient health. Together, they highlight why medical AI must\ncarefully balance precision and sensitivity.\n7.\nWhich visualizations best explain the predictive performance of the developed solution?\n→ A Confusion Matrix heatmap is the most effective visualization because it plainly lays out\ntrue positives, true negatives, false positives, and false negatives in a single grid.\nComplementing this with a Feature Importance / Coefficient Bar Chart clearly demonstrates\nwhich biological factors drive those predictions. Furthermore, an ROC Curve illustrates how\nwell the model discriminates across various classification thresholds. Together, these\nvisualizations make model behavior transparent and intuitive for both technical reviewers and\nmedical professionals.	6b7b7e41e1effb3d6e3ece353ee63046d461931b9b8822b50e9fcfb5afa03b97	gemini-embedding-2	indexed	2026-10-08 15:07:51.621436
3aaa5758-8fef-4f03-acc1-eb5fd277b001	tenant-001	doc-eb33be1c8687	ver-e891bb59	project-001	1	2	2	Page 2	L2 Engineer 2–4 years Delivers features\nindependently\nL3 Senior Engineer 4–7 years Owns modules;\nmentors juniors\nL4 Lead Engineer 7–10 years Leads a squad; drives\ndesign and delivery\nL5 Principal Engineer 10–14 years Owns product area or\n/ Engineering multiple squads\nManager\nL6 Director 14+ years Owns a business unit\nor programme (for\nexample, Atlas)\nL7 VP / Head 18+ years Sets strategy across\nunits\nExperience is indicative. Promotion depends on demonstrated capability,\nnot years alone. Non-engineering functions (QA, Product, HR, Finance,\nSales) use the same levels with function-specific titles.\nThere are two growth tracks from L4: Technical (Principal,\nDistinguished Engineer) and Management (Manager, Director).\nEmployees may switch tracks once, with approval.\n3. Promotion Criteria\nCriterion What We Look For\nPerformance Rating of 4 or above in the last cycle and 3 or\nabove in the one before; no active warning or\nPIP\nMinimum tenure L1→L2: 18 months; L2→L3: 24 months; L3→L4:\nin level 30 months; L4→L5: 36 months\nReadiness at next Already performing at least 70% of the\nlevel responsibilities of the next level for 6 months	449d908712b75c7727acf7ce2ec44ed635355ed53d2ac802064f4cf16570485b	gemini-embedding-2	indexed	2026-10-08 15:07:53.304459
6aed710a-e4c7-4508-afda-402deb96744e	tenant-001	doc-eb33be1c8687	ver-e891bb59	project-001	2	3	3	Page 3	Skills and Matches the competency framework (see\ncompetencies Section 4)\nBusiness need An open role or expanded scope exists;\npromotion is not automatic\nValues and Role-model behaviour and no conduct issues\nconduct\nFast-track: Employees rated 5 may be considered after half the\nminimum tenure, with Department Head and Head of HR approval\n(limited to 3% of headcount each cycle).\n4. Skills Expected by Level (Engineering\nExample)\nSkill Area L2 L3 L4 L5\nTechnical Strong in Deep in 2 Designs Defines\ndepth one stack areas systems architecture\nDelivery Completes Owns Leads Owns\nfeatures modules squad programme\nend to delivery outcomes\nend\nQuality Writes Improves Sets quality Drives\ntests code gates engineering\nstandards excellence\nCommunication Clear Presents Manages Influences\nupdates to clients stakeholders leadership\nMentoring Helps Mentors Coaches Builds\npeers 1–2 leads talent\njuniors pipeline\n5. Promotion Cycles and Review Process	e86f4881f919f54750c3444b5a8a3d461661cf7b982961a54d3a7253799a993b	gemini-embedding-2	indexed	2026-10-08 15:07:54.242186
de0c1724-1428-45ac-bd41-7ef62025d9a9	tenant-001	doc-eb33be1c8687	ver-e891bb59	project-001	3	4	4	Page 4	Cycle Nomination Panel Effective\nWindow Review Date\nApril cycle (with 1 – 31 March 1 – 15 April 1 May\nannual review)\nOctober cycle (mid- 1 – 15 1 – 15 1 November\nyear) September October\n1. Nomination: Manager submits a promotion case in PeopleHub\nwith achievements, impact examples and evidence of next-level\nperformance.\n2. Peer and stakeholder input: At least 3 reviewers (including a\nclient or cross-team stakeholder where relevant).\n3. Department review: Department Head endorses or rejects with\nreasons.\n4. Promotion panel: Head of HR, Head of Department and a leader\nfrom another function (for L3 and above also an independent\ntechnical reviewer) evaluate cases, using a standard scorecard.\n5. Decision: HR communicates outcome within 7 days; unsuccessful\ncandidates receive a development plan.\n6. Compensation: Promotion increment is 8–15% of fixed pay, with\na minimum of the entry salary for the new level.\n6. Career Development\n• Every employee has an Individual Development Plan (IDP) agreed\nat mid-year check-in.\n• Internal job postings are open to employees with 12+ months in\ncurrent role and rating 3 or above.\n• Cross-project rotation is possible after 18 months, with manager\nand HR approval.\n• Career conversations with manager at least twice a year.\nExample: Rahul (Senior Engineer, L3, 3 years in level) has rated 4 in\nFY 2025–26 and 3 the year before. He led the Atlas notification service\nredesign and now mentors two juniors. His manager nominates him in\nthe March window with three stakeholder reviews. The panel approves	c691c5541f892d8120f9e7cf795214dc62b7a79a864a6d5fe03fc0ed1a3a53d6	gemini-embedding-2	indexed	2026-10-08 15:07:55.059358
d455bcd8-f176-42be-a54a-482725ebc899	tenant-001	doc-eb33be1c8687	ver-e891bb59	project-001	4	5	5	Page 5	his promotion to Lead Engineer (L4), effective 1 May 2026 with a 12%\nincrement.\n7. Appeals\nEmployees not selected can ask for feedback within 7 days and may\nraise a grievance under NXR-HR-PRC-010 if they believe the process\nwas unfair.	1f54b0ebe86397c647f8c9b4ddc85aba0325777a785f042e0a4783b7f93edd91	gemini-embedding-2	indexed	2026-10-08 15:07:55.834035
5f0c6c57-db9e-4c04-8dd3-ca73acb186bb	tenant-001	doc-8405e29cdc24	ver-25afcb85	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nRemote Work Security Guidelines\nDocument NXR-IT-GDL-008\nID\nVersion 2.5\nEffective 1 April 2026\nDate\nOwner Information Security Office (CISO: Dr. Farhan\nQureshi)\nApplies To All employees, contractors and interns working\noutside Nexora offices\n1. Purpose\nTo protect Nexora and client data when employees work from home,\nclient sites, travel or any non-office location. These guidelines support\nISO 27001 requirements and client security clauses (for example, those\nin the Project Meridian banking contract).\n2. VPN Usage\n• Connect to the Nexora VPN (GlobalProtect) before accessing\nany internal system, code repository, staging environment or client	2a12ef6263956ffb3c58871d0b764f89aebaa352144ea6c7d4e3472ada0cd04d	gemini-embedding-2	indexed	2026-10-08 15:07:56.995126
4a6425ad-e1e1-43a6-81f7-5cc7b2f1c885	tenant-001	doc-8405e29cdc24	ver-25afcb85	project-001	1	2	2	Page 2	network.\n• VPN must stay connected for the whole working session. Auto-\ndisconnect after 30 minutes of inactivity is enforced.\n• Do not share VPN credentials or install other VPN or proxy\nsoftware on company laptops.\n• Split tunnelling is disabled for engineers with access to client\nproduction data.\n• If VPN is not working, raise a P2 ticket on ServiceDesk. Do not\nuse workarounds such as personal email or personal cloud\nstorage.\n3. Password and Authentication Rules\nRule Requirement\nMinimum length 14 characters (passphrase recommended)\nComplexity Upper, lower, number and symbol, or four\nrandom words\nChange frequency Every 180 days, or immediately if\ncompromise is suspected\nReuse Never reuse any of the last 10 passwords or\npersonal-account passwords\nMulti-factor Mandatory for email, VPN, cloud consoles,\nauthentication (MFA) GitHub and PeopleHub\nPassword manager Use the company-approved vault; do not\nstore passwords in browsers, notes or chat\nSharing Never share passwords, MFA codes or\nOTPs, even with IT staff\n4. Device Protection\nControl Requirement	dcd64157c685196da1b8299bbefbc2ece3c2cf4eef8104ab64b0f9398e67c933	gemini-embedding-2	indexed	2026-10-08 15:07:57.604533
bd54c1b0-f9ab-466f-8e21-6c9d932a6b30	tenant-001	doc-43c0cbab0d45	ver-7bae6ae1	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nTraining and Development Policy\nDocument NXR-HR-POL-011\nID\nVersion 2.2\nEffective 1 April 2026\nDate\nOwner Learning & Development (Tanvi Kapoor)\nApplies To All confirmed employees; mandatory training applies\nto everyone\n1. Purpose\nTo build the skills Nexora needs for its projects and to support each\nemployee's growth through structured learning, certifications and\nmentoring.\n2. Types of Training\nType Description Examples	4a911392e0bab1d3529386342dc647351ad9dd84f0d6b6a601ad21d89fe0610b	gemini-embedding-2	indexed	2026-10-08 15:08:00.480819
1912ab99-ef83-40e0-89a9-902361d6d4e6	tenant-001	doc-8405e29cdc24	ver-25afcb85	project-001	2	3	3	Page 3	Device Use only the Nexora-issued laptop for work; no\npersonal devices for code or client data\nDisk encryption BitLocker or FileVault enabled (checked\nautomatically)\nEndpoint security Antivirus/EDR agent must be active; do not\ndisable or uninstall\nUpdates Install OS and security updates within 7 days of\nrelease\nScreen lock Auto-lock after 5 minutes; lock manually when\nleaving the desk\nPhysical security Do not leave laptops in cars or unattended in\npublic places\nUSB and external Blocked by default; exceptions need CISO\nstorage approval\nSoftware Install only from the company software catalogue\nFamily and Do not let others use the work laptop or view\nguests client information\nLost or stolen devices must be reported to security@nexora-\ntech.example and ServiceDesk within 2 hours. The device is remotely\nlocked and wiped.\n5. Public Wi-Fi and Network Rules\n• Do not use public Wi-Fi (cafés, airports, hotels) for work unless\nVPN is connected first.\n• Prefer a mobile hotspot over unknown networks.\n• Home Wi-Fi: use WPA2/WPA3 encryption, change the default\nrouter admin password, and keep router firmware updated.\n• Do not join networks asking for installation of certificates or apps.\n• Avoid confidential calls in public places; use headphones and\nprivacy screens when travelling.	7fcd5afcb7e0ead88f2db237fdbaa5ca9fade81ab7cd1350a4ce51fed57cedf3	gemini-embedding-2	indexed	2026-10-08 15:07:58.396086
8b401eb4-0929-4c18-ad45-9970ed855b1c	tenant-001	doc-8405e29cdc24	ver-25afcb85	project-001	3	4	4	Page 4	6. Data Handling\nData Class Examples Handling Rule\nPublic Marketing material No restriction\nInternal Policies, project Share only within Nexora\nplans\nConfidential Source code, Store in approved SharePoint/\ncustomer lists, GitHub; no personal email or\ncontracts messaging apps\nRestricted Client PII, financial Access on need-to-know basis;\nand payment data, encryption in transit and at\ncredentials rest; no local download\n• Do not copy client data to personal drives, USB, or AI tools that\nare not approved by Nexora.\n• Print only when necessary and shred documents after use.\n• Take screenshots and photos of screens only with permission.\n• Follow the data retention rules in the Employee Data Management\nProcedure (NXR-HR-PRC-014).\n7. Phishing and Incident Reporting\n• Verify unexpected links, attachments and payment or credential\nrequests. Use the Report Phishing button in Outlook.\n• Report any suspected incident (malware, data leak, wrong-\nrecipient email) to the Security Operations Centre immediately via\nsecurity@nexora-tech.example or the 24×7 line,\n+91-20-5550-0199.\n• Do not attempt to investigate or delete evidence yourself.\n• Quarterly phishing simulations are run. Repeated failures lead to\nrefresher training.\nExample: Ananya receives an email that looks like it comes from the\nAtlas client's finance lead asking for a payment API key. She notices the	4335dc944c8944ce08d8ec40cef49640a2cd0a24784bb0978fffdd52531eabba	gemini-embedding-2	indexed	2026-10-08 15:07:59.037786
2cb14749-c2a8-4d88-9319-45d91483f22d	tenant-001	doc-8405e29cdc24	ver-25afcb85	project-001	4	5	5	Page 5	sender domain is slightly misspelled, clicks Report Phishing, and\ninforms the SOC. The domain is blocked within 20 minutes.\n8. Compliance\nAnnual security training and a quarterly self-attestation are mandatory.\nViolations may lead to access suspension and disciplinary action under\nthe Code of Employee Conduct.	68a2ce609432c6343cbd018fdad6af362ae9e20b76d562e09030c7fdfef304b3	gemini-embedding-2	indexed	2026-10-08 15:07:59.609743
7775e0a8-db9d-4a0a-86f3-c6b274cd739f	tenant-001	doc-a2d6def96248	ver-cfcc98e6	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nTravel and Expense Policy\nDocument NXR-FIN-POL-013\nID\nVersion 3.0\nEffective 1 April 2026\nDate\nOwner Finance (Controller: Ramesh Patil) with Admin &\nTravel Desk\nApplies To All employees travelling on company business\n1. Purpose\nTo ensure business travel is approved, cost-effective and properly\ndocumented, and that reimbursements are fair and prompt.\n2. Business Travel Approval\nTravel Type Approver Lead Time\nDomestic, up to Reporting Manager 3 working days\n3 days	63fcb3b1899d3911f0e8b72191a00c132c857eb4a8ee426064b7105292c1fbd4	gemini-embedding-2	indexed	2026-10-08 15:08:04.730784
7a73006e-b736-4ea3-ae2f-6eb3722e87fa	tenant-001	doc-a2d6def96248	ver-cfcc98e6	project-001	1	2	2	Page 2	Domestic, more Manager + Department Head 5 working days\nthan 3 days\nInternational Department Head + Finance 15 working days\nController; CFO approval for (visa and\nL5 and above booking)\nClient-mandated Manager (client email As per client\ntravel attached) need\nRaise a request on PeopleHub → Travel. Bookings are made only\nthrough the Nexora Travel Desk (travel@nexora-tech.example) or the\napproved booking tool. Non-approved travel is not reimbursed.\n3. Transportation\nMode Entitlement\nAir (domestic) Economy class; book at least 7 days ahead; lowest\nlogical fare\nAir Economy; Premium Economy for flights over 8\n(international) hours, L5 and above\nTrain AC 2-tier (L1–L4); AC 1st class or Executive Chair\n(L5+)\nLocal travel Metro/bus or app-based cab (Mini/Sedan); auto-\nrickshaw for short distance\nPersonal car ₹12 per km; bike ₹5 per km, with a log of distance,\npurpose and parking/toll bills\nAirport Cab as per local travel rules\ntransfers\nCancellation charges resulting from a personal reason are borne by the\nemployee.	e250779a35eee4ae57948334e9eb748f105c21cae27c2d57d878aa0e50304679	gemini-embedding-2	indexed	2026-10-08 15:08:05.376688
78c416fc-9842-4ff9-a79c-52cde5fe6f68	tenant-001	doc-a2d6def96248	ver-cfcc98e6	project-001	2	3	3	Page 3	4. Accommodation\nCity Tier L1–L3 L4–L5 L6 and\nabove\nTier 1 (Mumbai, Delhi NCR, ₹5,500 ₹7,500 ₹10,000\nBengaluru, Hyderabad, Pune, per night\nChennai)\nTier 2 (Ahmedabad, Jaipur, Kochi, ₹4,000 ₹5,500 ₹7,500\netc.)\nInternational Up to $200 $300\n$150\nHotels should be on the approved list where possible. Stay with friends\nor family is not reimbursed. Laundry is allowed for stays of 4 or more\nnights up to ₹500.\n5. Meals and Daily Allowance (Per Diem)\nLocation Daily Meal Breakdown\nLimit\nTier 1 city ₹1,200 Breakfast ₹250, Lunch ₹400, Dinner\n₹550\nTier 2 / ₹900 Breakfast ₹200, Lunch ₹300, Dinner\nother ₹400\nInternational $45 As per country guide\nAlcohol is not reimbursable. Client entertainment up to ₹2,500 per\nperson needs pre-approval and must list attendees and purpose.\n6. Other Eligible Expenses	be01da4a0a68a6600e4f0ceee7c43c9503f8c4096325c6a754e5bc48099b3254	gemini-embedding-2	indexed	2026-10-08 15:08:05.967366
8ecd5252-ecf3-457c-ba3d-6d1ce72cf897	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-a8180f3bb43d	ver-83a8a46e	project-001	1	2	2	Page 2	Parents / parents- Optional top-up of ₹3,00,000; premium paid by\nin-law employee through payroll\nCoverage starts Day one of employment\nMaternity Up to ₹75,000 (normal) / ₹1,00,000 (C-section);\nno waiting period\nPre-existing Covered from day one\nconditions\nPre/post 30 days before and 60 days after\nhospitalisation\nCashless network 6,500+ hospitals, including Ruby Hall (Pune),\nManipal (Bengaluru) and Apollo (Hyderabad)\nAnnual health Free for employee and spouse at partner labs\ncheck-up\n3. Life and Accident Insurance\nBenefit Cover\nGroup Term Life 3 × annual fixed pay, capped at\n₹75,00,000\nGroup Personal Accident ₹30,00,000 (death or permanent total\ndisability)\nCritical illness (employee ₹3,00,000 lump sum\nonly)\nNominees are updated in PeopleHub. Employees should review\nnominees after marriage, birth of a child or other life events.\n4. Allowances and Reimbursements	ce28c54170559151c14b056826eff4a9b71446d555ee8ac8674b283537b68100	gemini-embedding-2	indexed	2026-10-10 10:33:58.641566
9eeefe96-f887-427d-bb48-d93ed425b76d	tenant-001	doc-43c0cbab0d45	ver-7bae6ae1	project-001	1	2	2	Page 2	Mandatory Required for all Information security, POSH,\nemployees Code of Conduct, data\nprivacy\nRole- Linked to job role and Cloud architecture for Atlas,\nbased project needs secure coding, testing\nautomation\nLeadership For L4 and above and People management,\nhigh-potential stakeholder communication\nemployees\nSelf-driven Chosen by employee Online courses, conferences\nand approved by\nmanager\n3. Eligibility\nGroup Eligibility\nProbationers Mandatory and onboarding training\nonly\nConfirmed employees (6+ Learning budget, certifications,\nmonths) conferences\nEmployees with rating 2 or 1 Only training in the improvement\nplan\nInterns Internal bootcamp only\n4. Annual Learning Budget (per employee,\nper financial year)\nLevel Budget Notes\nL1–L3 ₹25,000 Courses, books, certifications	14ae717fe1db5edd241ca16ef044537b2ece5221d726ef3462b361ba1d402989	gemini-embedding-2	indexed	2026-10-08 15:08:01.272266
1e01e6b8-add0-4fcd-8a6c-19743c670575	tenant-001	doc-43c0cbab0d45	ver-7bae6ae1	project-001	2	3	3	Page 3	L4–L5 ₹40,000 Includes one conference per\nyear\nL6 and above ₹60,000 Includes leadership programmes\nUnused budget does not carry forward. Teams may pool budget for\ngroup workshops with L&D approval. Each employee also gets 5 paid\nlearning days per year for courses, exams or conferences.\n5. Approved Courses and Certifications\nApproved providers: Coursera for Business, Udemy Business,\nPluralsight, the internal Nexora Academy, and certification bodies listed\nbelow.\nTrack Approved Certifications (examples)\nCloud AWS Solutions Architect, Azure Administrator,\nGoogle Cloud Professional\nSecurity CISSP, CEH, CompTIA Security+\nData and AI Databricks Data Engineer, Azure Data Scientist,\nTensorFlow Developer\nQuality ISTQB Advanced, Selenium certification\nAgile and PMP, CSM, SAFe Practitioner\nManagement\nCourses not on the list can be approved if they clearly support the role\nand project (L&D decision within 3 working days).\n6. Certification Support\n• Exam fee: Fully reimbursed on first attempt after passing, within\nthe learning budget. Retake fees are borne by the employee.\n• Exam leave: 1 paid learning day per exam plus 2 study days for	3ceaac1cf0f067861473abd037889cb57534e0930ebaca79f42ce205e2fed347	gemini-embedding-2	indexed	2026-10-08 15:08:01.853785
78d2ba92-d93a-41c6-b756-9869f7b957db	tenant-001	doc-43c0cbab0d45	ver-7bae6ae1	project-001	3	4	4	Page 4	exams above ₹30,000 in fee.\n• Certification bonus: ₹5,000 for associate-level and ₹10,000 for\nprofessional/expert-level certifications aligned to business needs.\n• Service agreement: Training sponsored above ₹50,000 requires\na 12-month service commitment. If the employee leaves earlier,\nthe cost is recovered pro-rata from F&F.\n7. How to Apply\n1. Select the course on PeopleHub → Learning → Request\nTraining.\n2. Manager approves (for alignment with project needs) within 3\nworking days.\n3. L&D validates budget and issues the payment or reimbursement\nvoucher.\n4. Employee completes the course, uploads the certificate within 15\ndays, and shares learning in a team session.\n8. Evaluation of Training\n• Level 1 – Reaction: Feedback survey after each programme\n(target 4.2/5 or above).\n• Level 2 – Learning: Assessment or certification score.\n• Level 3 – Application: Manager review at 60 days on whether\nskills are used on the project.\n• Level 4 – Impact: L&D reports annually on productivity, quality\nand retention outcomes.\nL&D reviews training effectiveness in the Annual HR Report.\n9. Mentoring and Internal Programmes\nNexora Academy runs a 12-week Cloud Engineering Bootcamp,	db46bed65b27fbc741edd7f9fc3ebda9a387c93f191f4e74f89768e872760007	gemini-embedding-2	indexed	2026-10-08 15:08:02.619526
a29a07cd-a5ce-4b0f-b134-65a2f25265c8	tenant-001	doc-43c0cbab0d45	ver-7bae6ae1	project-001	4	5	5	Page 5	quarterly tech talks, and a mentoring programme pairing each L1–L3\nemployee with a senior mentor for 6 months.\nExample: Aditi (Senior Engineer, L3) enrols in the AWS Solutions\nArchitect – Professional exam costing ₹26,000. Her manager approves it\nfor the Atlas migration. She takes 3 learning days, passes on her first\nattempt, claims the fee within her ₹25,000 budget plus ₹1,000 from the\nmanager's team pool, and receives a ₹10,000 certification bonus. No\nservice commitment applies because the cost is under ₹50,000.	67fb19add87dd2cc8684c4b1e5dcdf527adc63a60e8e16dea5b0240b40b4e90c	gemini-embedding-2	indexed	2026-10-08 15:08:03.512521
dff20b6a-5715-4c9f-b206-c33afd92a9a5	tenant-001	doc-fad3ce481e4b	ver-3734fea0	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nWork From Home (Hybrid Work) Policy\nDocument ID NXR-HR-POL-003\nVersion 2.1\nEffective Date 1 April 2026\nOwner Head of HR with CTO (Sanjay Kulkarni)\nApplies To Eligible employees in India offices\n1. Purpose\nNexora follows a hybrid model: three days in office and two days from\nhome each week. This policy explains who can work from home (WFH),\nhow to request it, expected working hours, equipment support and\nproductivity expectations.\n2. Eligibility\nCategory Eligibility\nConfirmed employees (all levels) Standard hybrid: 2 WFH\ndays per week	e369c1f834f643495ff65db29e6d2f57c7fe208944c1766845771b3c14994dd7	gemini-embedding-2	indexed	2026-10-08 15:08:09.078355
72b9615c-51c7-439f-9a16-80697974088d	tenant-001	doc-fad3ce481e4b	ver-3734fea0	project-001	1	2	2	Page 2	Employees on probation Up to 1 WFH day per week,\nwith manager approval\nInterns and trainees Office-based; WFH only for\nexceptions\nRoles needing physical presence (IT Not eligible unless\nAdmin, Facilities, Hardware Lab, approved by HR\nReception)\nFully remote roles Only if stated in offer letter\n(currently 14 employees)\nWFH is a facility, not an entitlement, and may be withdrawn for\nperformance or conduct reasons after written notice.\n3. Approval Process\n1. Standard hybrid days: Teams agree a fixed anchor day in office\n(for example, Tuesday and Thursday for Project Atlas squads). No\nper-day approval is needed.\n2. Extra WFH days (up to 10 per year): Request in PeopleHub at\nleast 1 working day ahead. Manager approves.\n3. Extended WFH (more than 2 weeks, for example, medical or\nrelocation): Written request to manager and HR Business\nPartner. Maximum 8 weeks, renewable once.\n4. Working from another city or state: Needs HR and IT Security\napproval for tax, labour-law and data-security reasons.\n5. Working from outside India: Not permitted without Legal, HR\nand Finance approval.\n4. Working Hours and Availability\n• Be available online 11:00 AM – 4:00 PM (core hours) on WFH\ndays; total working hours remain 8.\n• Mark attendance on PeopleHub Mobile at start and end of day.	1e8d60e08b0cdd4b1ed394a311124462de4f8238e3b6c610458d0dd8ab1bbecc	gemini-embedding-2	indexed	2026-10-08 15:08:09.677794
a04afa19-1526-4176-93d8-f25e9948fa09	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-75f8446029de	ver-3e899ce9	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Leave Policy\nDocument NXR-HR-POL-001\nID\nVersion 3.2\nEffective 1 April 2026\nDate\nOwner Head of HR (Meera Iyer)\nApplies To All confirmed employees and probationers at Pune,\nBengaluru and Hyderabad offices\nLeave Year 1 April – 31 March\n1. Purpose\nThis policy sets out the types of leave available at Nexora, who is\neligible, how balances are calculated, how leave is approved, and how\nunused leave is carried forward. Leave is recorded in PeopleHub, the\ncompany HRMS.\n2. Types of Leave and Entitlement	2a64f9bb558187b71947f8d42c34e86f236822443e8730d442be268ab9e5005b	gemini-embedding-2	indexed	2026-10-10 10:34:15.358782
fee2a40a-792d-4b0d-9e2c-47ba79d31e29	tenant-001	doc-a2d6def96248	ver-cfcc98e6	project-001	3	4	4	Page 4	Visa and travel insurance (international), airport lounge (only if included\nin card/ticket), Wi-Fi/data when travelling (up to ₹500 per trip), and\nparking and toll charges. Not eligible: fines, personal shopping, mini-\nbar, in-room entertainment, personal phone calls, or upgrades without\napproval.\n7. Advances\nUp to 75% of estimated cost can be requested 5 working days before\ntravel. Unused advance must be returned or settled within 10 days of\nreturn.\n8. Reimbursement Process\n1. File the expense report on PeopleHub → Expenses within 15\ndays of return (claims after 45 days are rejected).\n2. Attach original receipts for each item above ₹300; GST invoices in\nthe company name where available.\n3. Manager approves within 3 working days.\n4. Finance validates policy compliance and pays within 7 working\ndays of approval with the next payroll or by bank transfer.\n5. Exceptions (over-limit spending) need Department Head approval\nbefore the trip.\nExample: Sameer (Lead Engineer, L4) travels from Pune to Bengaluru\non 12–14 August for a Meridian client workshop. Approved by manager\nand Department Head. Economy flight ₹5,800; hotel 2 nights at ₹7,200\nper night; meals 3 days at ₹1,000 per day; cabs ₹1,350. Total ₹24,550.\nHe files the claim on 18 August with receipts, and Finance reimburses it\non 28 August.\n9. Compliance	8c78a46bd197626b48c18df5995f4eede8548db98f9564b45aac6e5288f5e885	gemini-embedding-2	indexed	2026-10-08 15:08:06.919816
66cc8a19-c45f-4b88-ad44-d262b27e48a8	tenant-001	doc-a2d6def96248	ver-cfcc98e6	project-001	4	5	5	Page 5	False claims, duplicate claims or altered bills are violations of the Code\nof Employee Conduct. Finance conducts random audits of 10% of claims\neach quarter.	52b601bcd767d1db5f4795512fe123d37b01c7701ef45f2ee009020c154367a5	gemini-embedding-2	indexed	2026-10-08 15:08:07.869567
24881e6e-96d1-4b05-b583-f6a9f4d52d3f	tenant-001	doc-fad3ce481e4b	ver-3734fea0	project-001	2	3	3	Page 3	• Keep Microsoft Teams status current and respond to messages\nwithin 30 minutes during core hours.\n• Attend all scheduled stand-ups and client calls with camera on,\nunless the meeting owner says otherwise.\n• Out-of-hours work is not expected. Overtime rules in the\nAttendance Policy apply.\n5. Equipment and Allowances\nItem Support Provided\nLaptop Company-issued; only this device may be used\nfor work\nMonitor, keyboard, Collect from office or claim one-time\nmouse reimbursement\nDesk and chair One-time ₹10,000 (once every 3 years, bills\nsetup required)\nInternet and ₹1,500 per month, paid with salary for\nelectricity employees on regular hybrid\nHeadset One company-provided headset on request\nTechnical issues Raise a ticket on ServiceDesk; remote support\nwithin 4 working hours\nEmployees must keep a stable internet connection (at least 25 Mbps\nrecommended) and a quiet workspace for calls. Company equipment\nmust be used as per the Remote Work Security Guidelines (NXR-HR-\nPOL-008).\n6. Productivity Expectations\n• Goals and deliverables are tracked through Jira sprints and\nweekly 1:1s. Output matters more than hours online.\n• Teams run a daily 15-minute stand-up and a weekly planning	3e86f642ad72d61faf297d88b0eb82ba03c3cfdcf28e91dd248364d0a02cbfc5	gemini-embedding-2	indexed	2026-10-08 15:08:10.24783
918b7e04-8aa7-4617-a074-530d7ab4f1a0	tenant-001	doc-fad3ce481e4b	ver-3734fea0	project-001	3	4	4	Page 4	session.\n• If sprint commitments are repeatedly missed or a person is\nunreachable during core hours, the manager may reduce WFH\ndays after discussion and a written note to HR.\n• Client contracts that mandate on-site presence (for example, the\nMeridian programme for a banking client) override this policy for\nnamed team members.\nExample: Neha (Engineer, L2) is on the Atlas payments squad. Her\nsquad's anchor days are Tuesday and Wednesday, and she chooses\nThursday as her third office day. She works from home on Monday and\nFriday. If she wants to work from home on Thursday as well, she raises\nan extra WFH request in PeopleHub one working day ahead, and it\ncounts towards her 10 extra days for the year.\n7. Health and Safety\nEmployees are responsible for a safe, ergonomic workspace. Injuries\noccurring during working hours at home should be reported to HR within\n24 hours.\n8. Policy Review\nThe policy is reviewed annually in March. Feedback can be sent to\nhr@nexora-tech.example.	9be6bd53b70e00eadd59486033719eef6f0df961540d8ca56e94f5fbc1054983	gemini-embedding-2	indexed	2026-10-08 15:08:11.046324
639bc008-9d09-446c-84cf-e6cd7135fb36	a3424830-6d45-4ad8-a43b-a5fdf70d691d	doc-15c4f8adcd3f	ver-0a89f509	project-001	0	1	1	General Overview	Acme Corporation Secret Policy: All Acme employees receive quarterly innovation bonuses of $5000.	8ad202f3a48fc3b036ab2129764828d4d2a076b4170676d1a1b7070326a9cae1	gemini-embedding-2	indexed	2026-10-09 04:23:09.914459
c690c6b2-df3b-4e52-a9dd-45f3c10f94f3	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-6c4fc0bf754c	ver-4601908c	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Attendance Policy\nDocument ID NXR-HR-POL-002\nVersion 2.4\nEffective Date 1 April 2026\nOwner HR Operations (Rahul Deshmukh)\nApplies To All employees, including probationers and interns\n1. Purpose\nTo define working hours, attendance recording, late-arrival rules,\nabsence handling and overtime so that teams on projects such as Atlas,\nMeridian and Beacon can plan reliably.\n2. Working Hours\nItem Standard\nWorking days Monday to Friday\nStandard hours 9:30 AM – 6:30 PM (9 hours including a 1-hour\nbreak)	4442de7aeada298428a7fc310b08326599fc593045e9cba8d4c3a2e15fd32611	gemini-embedding-2	indexed	2026-10-10 10:33:52.687084
072de71a-e8a9-4677-88d1-c2d46694fb23	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-6c4fc0bf754c	ver-4601908c	project-001	1	2	2	Page 2	Core collaboration 11:00 AM – 4:00 PM (all employees available)\nhours\nFlexible start 9:00 AM – 10:30 AM, provided 8 working hours\nwindow are completed\nMinimum daily 8 hours for a full day; 4 hours for a half day\nhours\nSupport/NOC roles Shift-based: General (9:30–18:30), Evening\n(14:00–23:00), Night (22:00–07:00)\nShift employees receive a shift allowance (see Employee Benefits\nHandbook, NXR-HR-POL-004).\n3. Attendance Recording\n• Office: Swipe in and out using the access card at the entry\nturnstile. Biometric is used as backup.\n• Work from home: Check in and out on PeopleHub Mobile (geo-\ntag optional) and keep Teams status "Available" during core\nhours.\n• Client site: Mark "On Duty" in PeopleHub with client name and\napproval from manager.\n• Attendance is locked on the 25th of each month for payroll.\nCorrections must be raised by the 24th.\n• Missed swipes may be regularised up to 3 times per month with\nmanager approval.\n4. Late Arrival Rules\nArrival Time Treatment\nUp to 10:30 AM (flexible Normal, if 8 hours completed\nwindow)\n10:31 – 11:00 AM "Late mark" (grace limit: 3 per month)	a3561fa7798bbae4524a6d4c7d9711225af5ead44239ead00350ed93e6a06cc4	gemini-embedding-2	indexed	2026-10-10 10:33:53.293303
093c2e61-8860-4487-ae84-6983de5c37c8	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-6c4fc0bf754c	ver-4601908c	project-001	2	3	3	Page 3	After 11:00 AM without prior Half-day leave deducted\napproval\n4th late mark in a month 0.5 day CL deducted\n8 or more late marks in a Manager counselling; written warning\nquarter if repeated\nExample: Priya reaches the Pune office at 10:50 AM on three different\ndays in October. These are three late marks, so no deduction. On a\nfourth day she arrives at 10:45 AM, so 0.5 day CL is deducted.\nApproved exceptions: documented medical appointments, public\ntransport disruption declared by city authorities, and approved client-site\ntravel.\n5. Absence Handling\nSituation Action\nPlanned absence Apply leave in advance (see Leave\nPolicy, NXR-HR-POL-001)\nUnplanned absence Inform manager by 10:00 AM via phone\nor Teams; apply leave within 2 working\ndays of return\nAbsent without information Marked LOP; verbal warning\nfor 1 day\nAbsent without information Notice to show cause issued by HR\nfor 3 or more consecutive\ndays\nAbsent without information Treated as absconding; employment\nfor 7 or more consecutive may be terminated after notice to the\ndays registered address\n6. Overtime and Compensatory Off	ac499a23f714e4d7a24b5776c3cf04abbe6e7a1f2ba5fbbac52f3d045a9ec377	gemini-embedding-2	indexed	2026-10-10 10:33:53.854243
02e8d600-6944-413a-b4aa-320c9cb5d875	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-6c4fc0bf754c	ver-4601908c	project-001	3	4	4	Page 4	• Overtime is not paid for managerial and exempt roles (L4 and\nabove).\n• For L1–L3 and shift support staff, work beyond standard hours is\neligible only when pre-approved in writing by the manager.\n• Weekend or holiday work of 4+ hours earns 0.5 day comp-off; 8+\nhours earns 1 day comp-off.\n• Production support (on-call) rotation: ₹1,500 per weekend day on\ncall and ₹600 per weekday night of on-call.\n• Maximum overtime: 50 hours per quarter, in line with state shops-\nand-establishments rules.\nExample: During the Project Meridian go-live on Saturday 14 June,\nKaran (QA Engineer, L2) works 9 hours with manager approval. He\nreceives 1 comp-off, to be used within 60 days.\n7. Roles and Responsibilities\n• Employees: Record attendance accurately, communicate\nabsences early.\n• Managers: Review the team's attendance dashboard weekly and\napprove regularisations within 2 working days.\n• HR Operations: Run the monthly attendance report and share\nexceptions with HR Business Partners by the 27th.\n8. Violations\nFalsifying attendance (proxy swipes, edited logs) is a serious offence\nunder the Code of Employee Conduct and may lead to termination.	f2e9a601d1d36ac8c0dabe4b7f9bd50be31c8cd35c4e54ce0beaede7894089fd	gemini-embedding-2	indexed	2026-10-10 10:33:54.535347
d8ca83a5-c683-4985-9f61-43b8be08d9d4	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-a8180f3bb43d	ver-83a8a46e	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Benefits Handbook\nDocument ID NXR-HR-HBK-004\nVersion 4.0\nEffective Date 1 April 2026\nOwner Compensation & Benefits (Anita Rao)\nInsurance Group health: Medisure TPA; Life and accident:\nPartners Suraksha Life\n1. Introduction\nThis handbook summarises the benefits available to Nexora employees\nand how to claim them. Detailed terms are in the insurer policy\ndocuments available on PeopleHub under Benefits.\n2. Health Insurance\nFeature Details\nPlan type Group Mediclaim, family floater\nSum insured ₹5,00,000 per family per year\nCovered members Employee, spouse, up to 2 children	430e2bc0fbe704950fbf909188f6ad6ed44a9a2522fbf953c271393bb5d32a12	gemini-embedding-2	indexed	2026-10-10 10:33:58.018594
49ea0c64-cf65-4522-b50c-1672f7b7eb0a	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-a8180f3bb43d	ver-83a8a46e	project-001	2	3	3	Page 3	Allowance Amount Frequency Notes\nMeal card ₹2,200 per Monthly Pre-tax meal\nmonth vouchers on\nPluxee-type card\nWellness ₹12,000 Annual Gym, yoga,\ncounselling, fitness\napps; bills required\nInternet ₹1,500 per Monthly See WFH Policy\n(hybrid) month\nMobile and ₹800 per month Monthly Managers L4 and\ndata above\nNight shift ₹300 per night Per shift Support staff on\n22:00–07:00 shift\nRelocation Up to ₹50,000 One-time Needs 12-month\n(new joiners) service commitment\nReferral ₹25,000 (L1–L3) Per hire Paid after referred\nbonus / ₹50,000 (L4+) hire completes 6\nmonths\nLong service 5 years: ₹25,000 One-time\naward gift voucher; 10\nyears: ₹75,000\n5. Retirement and Statutory Benefits\n• Provident Fund (PF): 12% of basic pay by employee and 12% by\nemployer.\n• Gratuity: Payable after 5 years of continuous service as per the\nPayment of Gratuity Act, 1972.\n• ESI: Applicable only where wages fall under the statutory ceiling.\n• Professional tax and TDS: Deducted as per applicable law.\nInvestment declarations are due by 15 January.	45a095c960052162c5dc3737e3b1132c652e91c913f1f63126b8550a3d66cd8a	gemini-embedding-2	indexed	2026-10-10 10:33:59.504736
0c3abd48-5209-48ec-90fd-946266f3fda8	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-a8180f3bb43d	ver-83a8a46e	project-001	3	4	4	Page 4	6. Employee Discounts and Perks\nPartner Offer\nCult-style fitness network 25% off membership\nCloud and software partners Free personal cloud credits up to\n(internal tie-ups) $100 per year\nOnline learning marketplace 30% off personal subscriptions\nCab partner 15% off airport rides\nCompany merchandise store 20% employee discount\nQuarterly team events, annual offsite and festival gifts are managed by\nthe Culture Committee.\n7. Eligibility Summary\nGroup Health & Allowances Referral Long\nLife Bonus Service\nConfirmed Yes Yes Yes Yes\nemployee\nProbationer Yes Yes (except After No\nrelocation until confirmation\nconfirmation)\nIntern Accident Meal card only No No\ncover\nonly\nContractor / No No No No\nconsultant\n8. How to Claim	27f40dd4b7d7ce2ebe3a005184c663e792cebb4965baa5c47187e002635428a9	gemini-embedding-2	indexed	2026-10-10 10:34:00.121043
f4f4d8d9-8905-46ef-b949-4caeab6c6cee	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-a8180f3bb43d	ver-83a8a46e	project-001	4	5	5	Page 5	Cashless hospitalisation\n1. Show the Medisure e-card at the network hospital desk.\n2. The hospital sends a pre-authorisation request to the TPA\n(approval usually within 4 hours).\n3. Pay only non-covered items at discharge.\nReimbursement claims (health or allowances)\n1. Submit the claim in PeopleHub → Claims with original bills,\ndischarge summary or invoices.\n2. Deadline: within 30 days of discharge or expense (45 days for\ninsurance claims).\n3. HR reviews within 5 working days; payment is made with the next\nsalary cycle.\nExample: Rohan (Senior Engineer, Pune) spends ₹18,400 on a gym\nmembership in July. He uploads the invoice by 31 July, receives\n₹12,000 under the annual wellness allowance and pays the remaining\n₹6,400 himself.\n9. Contacts\nBenefits helpdesk: benefits@nexora-tech.example. TPA helpline:\n1800-000-1234 (24 × 7).	026f1d982c2fd7267d64f90cf5d803880e53197ce9ae11af26250aed3388514c	gemini-embedding-2	indexed	2026-10-10 10:34:00.732878
5a9e9b92-5766-4604-ad80-6d542bebcdaa	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-24f027b6f4a7	ver-d1b53198	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Data Management Procedure\nDocument NXR-HR-PRC-014\nID\nVersion 2.1\nEffective 1 April 2026\nDate\nOwner HR Operations with Data Protection Officer (Neeraj\nBhatt)\nApplies To All HR staff, managers and anyone handling\nemployee data\n1. Purpose\nTo describe how Nexora creates, stores, uses, updates, retains and\ndisposes of employee records, and how privacy is protected in line with\nthe Digital Personal Data Protection Act, 2023 and applicable labour\nlaws.\n2. Employee Records\nThe official record of each employee is held in PeopleHub (system of\nrecord) and a secured digital folder.	bf1a024fc42b36287cebf1eaba2f38af5a4c2a04b0b9713f1854c3d274dafd47	gemini-embedding-2	indexed	2026-10-10 10:34:04.327896
c1a64619-7841-4c34-86e0-60d7ab39575a	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-24f027b6f4a7	ver-d1b53198	project-001	1	2	2	Page 2	Record Type Contents Storage\nPersonal Name, address, contact, PeopleHub\nemergency contact, ID proofs, (encrypted)\nphoto\nEmployment Offer letter, contract, role, PeopleHub + HR\nlevel, department, manager, SharePoint\njoining and confirmation dates\nPayroll and Salary, tax declarations, PF/ Payroll system,\nstatutory UAN, bank details, gratuity access-restricted\nnomination\nPerformance Goals, ratings, feedback, PIP, PeopleHub –\npromotions Talent module\nAttendance and Swipe logs, leave balances, PeopleHub\nleave WFH records\nMedical and Insurance enrolment, claim Benefits vault;\ninsurance details, sick leave certificates held only by HR\nBenefits\nDisciplinary and Show-cause notices, Restricted HR\ngrievance investigation reports folder\nExit Resignation, F&F, relieving PeopleHub + HR\nletter, exit interview SharePoint\nOnly data needed for a specific business or legal purpose is collected\n(data minimisation). Employees are informed of the purpose through\nthe Employee Privacy Notice, signed at joining.\n3. Data Access and Authorisation\nRole Access Level\nEmployee Own record (view; edit contact, bank and nominee\ndetails)	2d936e059596b371d28957d20b3cd8d87c7b4cec7decdc225c759c17c7bb2cd9	gemini-embedding-2	indexed	2026-10-10 10:34:04.952835
d4b92d53-9eb6-4446-abb7-3724b4177581	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-24f027b6f4a7	ver-d1b53198	project-001	2	3	3	Page 3	Reporting Team's attendance, leave, performance and\nManager goals; no medical, bank or salary details\nHR Business Records of assigned departments (no payroll\nPartner details unless needed)\nHR Operations / Full access to employment and payroll data for\nPayroll processing\nFinance and Payroll and expense data on request\nAudit\nLegal and Case-specific records with written justification\nCompliance\nIT Admin System administration only; no content access\nwithout ticket approval\nLeadership Aggregated reports; individual data only when\nrequired for decisions (CEO/Head of HR approval)\n• Access is role-based, reviewed every quarter by HR and the\nInformation Security Office.\n• Access logs for sensitive records are retained for 12 months.\n• Sharing employee data with third parties (insurers, BGV agencies,\nauditors, payroll vendors, clients) requires a signed data-\nprocessing agreement or consent.\n• Client requests for staff details (for example, for background\nchecks on Atlas team members) are shared only with employee\nconsent and limited to what the contract requires.\n4. Updating Records\n• Employees update personal details in PeopleHub under My\nProfile; changes to name, marital status or bank account need\nsupporting documents verified by HR within 5 working days.\n• HR updates job-related changes (promotion, transfer, increment)\non the effective date.\n• Annual data-verification drive in April: each employee confirms\ntheir details.	3ca43bef70e591309363e79b055897bbce10abeaaf5ec69aea696bbb547c0983	gemini-embedding-2	indexed	2026-10-10 10:34:05.709891
33d2564c-7ecc-4062-aebe-c8606203f961	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-24f027b6f4a7	ver-d1b53198	project-001	3	4	4	Page 4	• Corrections of errors are logged with date, reason and approver\n(audit trail).\n5. Retention Schedule\nRecord Retention Period After\nRetention\nRecruitment records of 12 months Delete\nunsuccessful candidates\nEmployment contract, 8 years after exit Secure\npersonnel file deletion\nPayroll, PF, gratuity and 8 years after exit (or as Archive then\ntax records per statute, whichever is delete\nlonger)\nAttendance and leave 5 years Delete\nPerformance records 5 years after exit Delete\nDisciplinary and 5 years after closure Delete\ngrievance files (longer if litigation\npending)\nPOSH inquiry records 5 years Secure\ndeletion\nMedical and insurance 3 years after exit Delete\nrecords\nCCTV and access logs 90 days Auto-\noverwrite\nLegal hold: Records required for an ongoing investigation or legal\nproceeding are retained until the Legal team lifts the hold.\n6. Privacy and Employee Rights	f74533585b8290d7a02a608ea2781505ccc842a53cec870b2e3e3cdf98be541e	gemini-embedding-2	indexed	2026-10-10 10:34:06.564343
520989a2-62e9-4cb0-a00f-0d61295823c6	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-24f027b6f4a7	ver-d1b53198	project-001	4	5	5	Page 5	Employees can: access their data, request correction, request erasure of\ndata no longer needed, withdraw consent for optional uses (for example,\nbirthday announcements, photos), nominate a person to exercise rights\nin case of death or incapacity, and raise a privacy complaint with the\nData Protection Officer at dpo@nexora-tech.example. Requests are\nanswered within 15 working days.\n7. Security and Breach Handling\nEmployee data is encrypted at rest and in transit; printing and local\ndownloads of restricted data are blocked. Any suspected data breach\nmust be reported to the Security Operations Centre immediately (see\nNXR-IT-GDL-008). The DPO assesses and informs affected employees\nand the Data Protection Board of India as required by law.\n8. Disposal\nPaper records are shredded, and digital records are deleted with\ncertified wiping. Disposal is logged and approved by HR Operations and\nthe DPO.\nExample: Pallavi leaves Nexora on 31 July 2026. Her personnel and\npayroll records will be kept until 31 July 2034. Her performance and\nattendance files will be deleted on 31 July 2031. When she asks in\nSeptember 2026 for her old payslips, HR provides them after verifying\nher identity, within 5 working days.	fa600deff8fa8c9eb31627653d38cf343109fc407636623907345886d3a093ff	gemini-embedding-2	indexed	2026-10-10 10:34:07.213434
d0bae014-8abc-462b-bfee-9bab21064f34	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-e8e98b8c83a3	ver-e85d905a	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Grievance Procedure\nDocument ID NXR-HR-PRC-010\nVersion 2.0\nEffective Date 1 April 2026\nOwner Employee Relations (Sunita\nJoshi)\nApplies To All employees and interns\n1. Purpose\nTo give every employee a safe, fair and timely way to raise work-related\nconcerns and have them resolved without fear of retaliation.\n2. What Is a Grievance?\nA grievance is a formal complaint about a work-related matter, for\nexample:\n• Unfair treatment, discrimination or favouritism\n• Workload or work-allocation concerns\n• Rating, increment or promotion decisions (after the feedback\nmeeting)	3f2e07a6895e237899c632f9d764b9714231196731f18e61c8a415650e61f713	gemini-embedding-2	indexed	2026-10-10 10:34:10.23813
cd56985a-db3f-454c-8b58-a56ef7ec4b46	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-e8e98b8c83a3	ver-e85d905a	project-001	1	2	2	Page 2	• Pay, leave or attendance errors\n• Manager or peer behaviour, bullying\n• Working conditions, facilities or safety\nOut of scope: Sexual harassment complaints (go to the Internal\nCommittee under the Code of Conduct), whistleblower or fraud reports\n(go to ethics@nexora-tech.example), and legal disputes or notices.\n3. How to Submit a Grievance\nChannel Details\nPeopleHub Help → Raise a Grievance (preferred; creates a ticket\nnumber)\nEmail grievance@nexora-tech.example\nIn person HR Business Partner or Employee Relations team\nAnonymous Ethics hotline (+91-20-5550-0177) or web form; limited\nfollow-up is possible\nEmployees are encouraged to first discuss minor issues informally with\ntheir manager or HR Business Partner. A formal grievance should\ninclude a clear description, dates, people involved, supporting\ndocuments and the resolution sought.\n4. Escalation Levels and Timelines\nLevel Handler Acknowledgement Resolution\nTarget\nLevel 0: Reporting Same day 3 working\nInformal Manager / HRBP days\nLevel 1: HR Business 1 working day 7 working\nFormal Partner days	7edf6966842a4d0bb1714b9fada209d22c5fae94ca867205c13c8db9ad07e9ee	gemini-embedding-2	indexed	2026-10-10 10:34:10.823925
9b09bc6b-7d9d-4fc4-bb37-4c9129cd4233	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-e8e98b8c83a3	ver-e85d905a	project-001	2	3	3	Page 3	Level 2: Head of HR 2 working days 15 working\nEscalation (Meera Iyer) with days\nDepartment\nHead\nLevel 3: Committee of 3 3 working days 30 working\nGrievance (HR Head, Legal days\nCommittee rep, senior leader\nfrom another\ndepartment)\nAn employee may escalate if no response is received within the stated\ntime or if unsatisfied with the outcome (within 7 working days of\nreceiving the decision). If the grievance involves the reporting manager\nor HRBP, the employee may go directly to Level 2.\n5. Investigation Process\n1. Intake: HR logs the case and assigns an investigator who has no\nconflict of interest.\n2. Acknowledgement: The employee receives a confirmation with a\nticket number and expected timeline.\n3. Fact-finding: Investigator interviews the complainant, the\nrespondent and witnesses, and reviews records such as emails,\nattendance and performance data.\n4. Fairness: Both sides get a chance to present their version.\nInterviews are documented and signed.\n5. Findings: A written report with findings and recommendations is\nprepared.\n6. Decision and communication: Outcome shared with the\nemployee in a meeting and by email.\n7. Closure: HR follows up after 30 days to confirm the resolution is\nworking.\n6. Possible Resolutions	5e36b9100e56a18c709d5eca74bb87d6d2df513f35c7ab5c247cb07c79d2867e	gemini-embedding-2	indexed	2026-10-10 10:34:11.831139
f797b14b-2d1d-4a43-aaf8-5f7fa3d66c47	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-e8e98b8c83a3	ver-e85d905a	project-001	3	4	4	Page 4	Clarification or mediation; correction of records (leave, pay, rating);\ncoaching or training for the manager; change of reporting line or team;\ndisciplinary action under the Code of Employee Conduct; process\nchanges. If the complaint is found unsubstantiated, no action is taken\nagainst the complainant unless it was made with malicious intent.\n7. Confidentiality and Non-Retaliation\n• Information is shared only with people who need it for the\ninvestigation.\n• Retaliation, including threats, unfair ratings, or exclusion, is a\nserious violation. Report retaliation directly to the Head of HR.\n8. Records and Metrics\nCases are retained for 5 years. HR reports quarterly to the leadership\nteam on grievance count, categories, average resolution time and repeat\nissues, without personal details.\nExample: Dev (Engineer, Project Atlas) raises a grievance on 4 August\nthat his on-call rota exceeded the agreed one week in three. His HRBP\nacknowledges the next day, reviews the rota with the delivery manager,\nand by 10 August the rota is corrected and Dev receives two comp-off\ndays. The case is closed after a 30-day check-in.	568c17a3ba07d11efb776069373469b219c547c50d4167d838522f9d508ad83e	gemini-embedding-2	indexed	2026-10-10 10:34:12.479928
8865ba65-fa03-4965-bf78-235c9bca642c	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-75f8446029de	ver-3e899ce9	project-001	1	2	2	Page 2	Leave Type Entitlement Eligibility Notes\n(per year)\nCasual Leave 8 days From date of Max 3\n(CL) joining consecutive\ndays\nSick Leave 8 days From date of Medical\n(SL) joining certificate\nneeded for\nmore than 2\nconsecutive\ndays\nEarned Leave 18 days After 3 months Planned leave;\n(EL) of service; notice required\naccrues 1.5\ndays/month\nMaternity 26 weeks (first Female As per Maternity\nLeave two children) employees Benefit Act,\nwith 80+ days 1961\nof service\nPaternity 10 working Confirmed To be taken\nLeave days male within 6 months\nemployees of birth\nMarriage 5 working days Confirmed Invitation or\nLeave employees, certificate on\nfirst marriage request\nBereavement 5 working days Immediate Applicable from\nLeave family (parent, day one\nspouse, child,\nsibling)\nCompensatory 1 day per All employees Must be used\nOff approved within 60 days\nweekend/\nholiday work\nday	04454685312e310f0bf4e615cdab00c8a2d1562d95913759713e6a4cc9492ccc	gemini-embedding-2	indexed	2026-10-10 10:34:15.937629
4fa78db3-0ff8-4392-ac92-ba6875d68ace	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-75f8446029de	ver-3e899ce9	project-001	2	3	3	Page 3	Loss of Pay As required When balance Deducted per\n(LOP) is exhausted day from\nmonthly salary\nJoining mid-year: CL and SL are credited pro-rata (rounded up to the\nnearest half day).\n3. Leave Balance\n• EL accrues on the last day of each month. CL and SL are credited\non 1 April.\n• Balances are visible in PeopleHub under My Leave → Balance.\n• Weekends and declared company holidays falling inside a leave\nperiod are not counted, except when they fall between two\nperiods of sick leave exceeding 5 days.\nExample: Arjun (Senior Engineer, Project Atlas) joins on 1 July 2026.\nHis CL and SL for the year are pro-rata: 8 × 9/12 = 6 days each. EL\nstarts accruing after he completes 3 months (from 1 October).\n4. Approval Process\nLeave Apply In Advance Approver\nDuration\n1–2 days 2 working days Reporting Manager\n3–5 days 7 working days Reporting Manager\n6–10 days 15 working days Reporting Manager\n+ Project/Delivery\nHead\nMore than 10 30 working days Delivery Head +\ndays HR Business\nPartner	978f58f3a913241d0446c2b876b3e9196e520a76d6d4ad7b5b35b8bc6c2debb6	gemini-embedding-2	indexed	2026-10-10 10:34:16.816756
83120558-a03a-482c-b25e-7b6b106bf1f6	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-75f8446029de	ver-3e899ce9	project-001	3	4	4	Page 4	Sick leave Inform manager before 10:00 Reporting Manager\n(unplanned) AM same day; apply within 2\nworking days of return\nSteps\n1. Employee applies in PeopleHub and selects leave type and dates.\n2. Manager approves or rejects within 2 working days. Unactioned\nrequests escalate automatically to the manager's manager.\n3. For client-facing roles, the employee names a backup colleague\nand updates the project calendar (for example, the Atlas sprint\nplanner).\n4. HR reviews leave exceeding 10 days and any pattern of leave\nadjacent to weekends or holidays.\nManagers may defer (not deny without reason) leave during critical\nrelease windows such as production go-live, giving an alternate date\nwithin 2 weeks.\n5. Carry-Forward and Encashment\nLeave Carry Forward Encashment\nType\nEarned Up to 30 days total Balance above 30 is encashed at\nLeave balance basic pay / 26 per day at year end\nCasual Not allowed; lapses No\nLeave on 31 March\nSick Up to 8 days No\nLeave accumulate (cap\n16)\nComp-off Lapses after 60 No\ndays\nOn separation, unused EL is encashed in the full-and-final settlement.\nNegative EL balance is recovered.	bab5d5a49327e0135f28572d3a1a33a5483bfee9746782c5b5f4c1ab712e5670	gemini-embedding-2	indexed	2026-10-10 10:34:17.410541
c5ca8f5e-4cbb-4d96-8fa7-5edde64732e5	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-75f8446029de	ver-3e899ce9	project-001	4	5	5	Page 5	6. Other Rules\n• Probation: Employees on probation may use CL, SL and\nstatutory leave. EL is available only after confirmation or with HR\napproval.\n• Public holidays: The company declares 11 holidays per year (list\npublished each January). Employees get 2 floating holidays.\n• Extended medical leave: Beyond available balance, up to 90\ndays of unpaid medical leave may be approved by HR on\nsubmission of medical documents.\n• Misuse: Falsified medical certificates or leave on false grounds\nare handled under the Code of Employee Conduct (NXR-HR-\nPOL-009).\n7. Roles and Responsibilities\n• Employee: Apply on time, hand over work, keep contact details\ncurrent.\n• Manager: Approve or reject within 2 working days and plan team\ncoverage.\n• HR Operations: Maintain the leave calendar, run year-end carry-\nforward on 1 April, resolve balance disputes within 5 working\ndays.\n8. Revision History\nVersion Date Change\n3.0 1 April Added 2 floating holidays\n2024\n3.1 1 April Paternity leave increased from 7 to 10 days\n2025	6d3e5a155e0c044d8ec4c6420f6cf0a3c869e8ca4ab632199ae9e29c24917795	gemini-embedding-2	indexed	2026-10-10 10:34:18.21084
58f0f097-3242-4b41-a57d-3ead35054fd6	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-75f8446029de	ver-3e899ce9	project-001	5	6	6	Page 6	3.2 1 April EL carry-forward cap raised from 24 to 30\n2026 days	99e5cee82921f562ad1ac0dff0d8fc4cf47ba96f55daf2f3da4d5b1bbc3fbef8	gemini-embedding-2	indexed	2026-10-10 10:34:19.135732
a7670daa-9c95-4cfc-bbfd-81e4dd0cf765	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-f86ce675b533	ver-897f5d21	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Offboarding Procedure\nDocument NXR-HR-PRC-007\nID\nVersion 2.2\nEffective 1 April 2026\nDate\nOwner HR Operations (Rahul Deshmukh)\nApplies To All employees leaving through resignation,\ntermination, retirement or end of contract\n1. Purpose\nTo ensure a respectful, orderly and secure exit, with proper knowledge\ntransfer, return of assets, deactivation of access and timely full-and-final\n(F&F) settlement.\n2. Resignation Process\n1. Employee submits resignation in PeopleHub → Separation and\nemails the reporting manager.\n2. Manager acknowledges within 2 working days and discusses\nreasons and retention options.	1b5af4f15e0ba385441126741567f2ece2a2d0e043b8004413490e5d4daf5bc7	gemini-embedding-2	indexed	2026-10-10 10:34:22.747763
57344fdf-1e78-48ab-bed9-818c270c89f4	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-f86ce675b533	ver-897f5d21	project-001	1	2	2	Page 2	3. HR Business Partner schedules an exit conversation within 5\nworking days.\n4. HR issues the resignation acceptance letter confirming the last\nworking day (LWD).\n5. Employee follows the exit checklist in Section 6.\n3. Notice Period\nCategory Notice Period\nProbationers 30 days\nConfirmed employees, L1–L3 60 days\nConfirmed employees, L4 and above 90 days\nContract and interns As per contract\n• Notice buy-out: Possible with Department Head and HR\napproval. The employee pays basic + fixed allowances for the\nshortfall days. Buy-out is not available during critical project\nphases or if a client contract requires named resources.\n• Leave during notice: Leave is not allowed in the last 15 days of\nnotice, except for medical emergencies. Unused earned leave is\nencashed in F&F.\n• Early release: Considered case by case if knowledge transfer is\ncomplete and the manager approves.\n• Garden leave or immediate release: The company may relieve\nan employee early with pay in lieu of notice.\n4. Knowledge Transfer (KT)\nA KT plan must be agreed within 5 working days of resignation\nacceptance.\nItem Details	798ab8ef4ffe45cfb6780fbdbbab8f66df525c99aa33ee728415c670c992e543	gemini-embedding-2	indexed	2026-10-10 10:34:23.396938
dbc61468-5593-486e-a0e7-41b27b660832	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-f86ce675b533	ver-897f5d21	project-001	2	3	3	Page 3	KT owner Resigning employee; supervised by the manager\nDuration Minimum 2 weeks for L1–L3; 4 weeks for L4+\nContent Code and architecture walkthroughs, runbooks,\nopen tickets, client contacts, credentials handover\n(via vault)\nDocumentation Confluence pages updated; recorded sessions\nstored in the project SharePoint\nSign-off Successor and manager confirm completion in\nPeopleHub\nExample: Rohit (Lead, Project Atlas) resigns on 1 August with a 90-day\nnotice. He documents the payment gateway integration, runs four\nrecorded sessions for his successor Meena, and completes sign-off by\n15 October, two weeks before his LWD of 30 October.\n5. Asset Return and Account Deactivation\nAsset / Access Owner Timeline\nLaptop, charger, IT Return on LWD; data wipe\naccessories after backup review\nAccess card, ID card, Admin LWD\nparking pass\nCorporate credit card, SIM, Finance / LWD\nmobile IT\nEmail, Teams, Jira, IT Disabled at 6:30 PM on\nGitHub, cloud consoles Security LWD\nVPN and MFA tokens IT Disabled on LWD\nSecurity\nShared passwords and Project Rotated within 24 hours\nAPI keys Lead	663cf8c970fa4985c1e27677ef9192446a332c93cc1fdeb2ca89bf9ded025332	gemini-embedding-2	indexed	2026-10-10 10:34:24.183162
7cf48b5a-9422-43ec-8c7f-f5aa3f218bf4	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-f86ce675b533	ver-897f5d21	project-001	3	4	4	Page 4	Email forwarding to IT 30 days, then deleted\nmanager\nMissing or damaged assets are charged at depreciated value and\nrecovered from F&F.\n6. Exit Checklist\n# Task Owner\n1 Submit resignation in PeopleHub Employee\n2 Complete KT and get sign-off Employee /\nManager\n3 Clear pending expense claims Employee /\nFinance\n4 Return assets Employee / IT /\nAdmin\n5 Complete exit interview and feedback form Employee / HR\n6 Obtain no-dues clearance from IT, Admin, All departments\nFinance, Library, Project\n7 Receive relieving letter and experience letter HR\n6A. Full-and-Final Settlement\n• Includes salary till LWD, EL encashment, gratuity (if eligible),\nbonus pro-rata where applicable, less recoveries (notice shortfall,\nloans, assets, training bond).\n• Paid within 30 days of LWD, subject to clearance of all dues.\n• Form 16 is issued by 30 June of the following year. PF transfer is\nsupported through the UAN portal.	814f11dd530c5f7b2d989621087d997e9b900da09d48ea836834f8f03a52f09c	gemini-embedding-2	indexed	2026-10-10 10:34:25.061753
68920f79-6b82-486e-9aca-9461b7c803d8	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-f86ce675b533	ver-897f5d21	project-001	4	5	5	Page 5	7. Exit Interview\nConducted by an HR Business Partner (not the reporting manager).\nResponses are confidential and shared only as aggregated themes with\nleadership.\n8. Rehire\nEmployees who leave in good standing with rating 3 or above are\neligible for rehire after a 6-month gap. Past service is not carried over\nunless approved by the Head of HR.	f86725cce78d4fad23f49fc01a2d7cce7e4141824bce00a7e2b281cbd52612c5	gemini-embedding-2	indexed	2026-10-10 10:34:25.685243
bac44c3c-2d3f-47e5-8afc-3b73e2a1c7b7	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ab5c26d1ac91	ver-4a758112	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nHR Department Annual Report: FY 2025–26\nReporting period: 1 April 2025 – 31 March 2026 | Prepared by: Meera\nIyer, Head of HR | Date: 24 April 2026\nDocument ID NXR-HR-RPT-015\nVersion 1.0\nAudience Executive Leadership Team and Board\n1. Executive Summary\nFY 2025–26 was a year of steady growth. Headcount grew from 372 to\n420 (+13%) as we staffed Project Atlas (payments platform), Project\nMeridian (banking reconciliation) and Project Beacon (internal HRMS\nrebuild). We hired 110 people, kept voluntary attrition at 12.9%,\ndelivered about 37 learning hours per employee, and rolled out the\nhybrid work model and PeopleHub 2.0.\n2. Employee Statistics (as of 31 March 2026)\nDepartment Headcount Share\nEngineering 232 55.2%\nQA 56 13.3%	a96f4882ec263ae95b61a5f4fc843f01c6703f91029ccd6217a22fb1d02caf11	gemini-embedding-2	indexed	2026-10-10 10:34:36.543886
92460dfb-10b1-4953-8c11-8d2b659fd5a9	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ab5c26d1ac91	ver-4a758112	project-001	1	2	2	Page 2	Data & AI 38 9.0%\nProduct & Design 34 8.1%\nSales & Pre-sales 22 5.2%\nIT & Admin 18 4.3%\nFinance 11 2.6%\nHR 9 2.1%\nTotal 420 100%\nMetric Value\nLocation split Pune 246 (58.6%), Bengaluru 118 (28.1%),\nHyderabad 56 (13.3%)\nWomen employees 160 (38.1%); 29% of leadership roles (L4 and\nabove)\nAverage age 31.4 years\nAverage tenure 3.2 years\nFully remote 14\nemployees\n3. Hiring\nMetric FY 2024–25 FY 2025–26\nTotal hires 94 110\nExperienced hires / Campus hires 78 / 16 86 / 24\nEmployee referrals 31% 38%\nAverage time to hire 41 days 36 days\nOffer acceptance rate 78% 84%\nCost per hire ₹62,000 ₹54,000	7263cbbe91362a95a00eca7224371a870da4f227cfc3071a2f6fd32b4988ae8d	gemini-embedding-2	indexed	2026-10-10 10:34:37.602882
fe132ae4-2b91-435a-9a2b-ae93d18f7edf	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ab5c26d1ac91	ver-4a758112	project-001	2	3	3	Page 3	Hires by department: Engineering 68, QA 14, Data & AI 10, Product &\nDesign 9, Sales & Pre-sales 5, HR/Finance/Admin 4 (total 110).\n4. Attrition\nMetric FY 2024– FY 2025–26\n25\nTotal exits 56 62\nVoluntary exits 47 51\nInvoluntary exits 9 11\nOverall attrition (annualised) 16.1% 15.7%\nVoluntary attrition 13.5% 12.9%\nAttrition in first year of service 24% of exits 21% of exits\nOverall attrition is calculated as exits ÷ average headcount (62 ÷ 396).\nTop reasons for leaving (exit interviews): higher compensation\nelsewhere (34%), career growth (27%), relocation or higher studies\n(16%), work-life balance (11%), others (12%). Engineering had the\nhighest attrition at 17.4%; HR and Finance the lowest.\n5. Training and Development\nMetric Result\nTotal learning hours 14,800 (average 37 hours per employee)\nLearning budget spent ₹1.12 crore (84% utilisation)\nCertifications completed 143 (AWS 46, Azure 31, Security 18,\nISTQB 22, others 26)\nNexora Academy Cloud 3 batches; 72 graduates\nBootcamp	d70a0307935dc4924eaac782159d1f75c44cede01cd255b269e0103a63a0ee5b	gemini-embedding-2	indexed	2026-10-10 10:34:38.349757
9cafcdc5-8f1c-436f-b619-8c09a8c437e2	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ab5c26d1ac91	ver-4a758112	project-001	3	4	4	Page 4	Mandatory training 100% (security, POSH, Code of\ncompletion Conduct)\nAverage programme 4.4 / 5\nfeedback\nMentoring pairs 96\n6. Performance Trends (FY 2025–26 Cycle)\nRating Share of Employees FY 2024–25\n5 – Outstanding 6% 5%\n4 – Exceeds 24% 22%\n3 – Meets 56% 58%\n2 – Needs Improvement 12% 13%\n1 – Unsatisfactory 2% 2%\n• Average increment: 8.4%; promotions: 38 employees (9.0%)\nacross April and October cycles.\n• 9 employees were placed on PIP; 5 completed successfully, 3\nexited and 1 is ongoing.\n• Mid-year check-in completion: 96%; goal-setting completion by 30\nApril: 98%.\n7. Employee Engagement and Well-being\nMetric FY 2024–25 FY 2025–26\nEngagement survey score 72% 78%\nParticipation 81% 90%\neNPS +18 +27	fd8f3f9d548ce6d7c8c57b19572983fb353e0a9efc623ccda90744223b7179fa	gemini-embedding-2	indexed	2026-10-10 10:34:39.147302
fc99fd7e-430c-4d9b-a786-8e6397f41711	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ab5c26d1ac91	ver-4a758112	project-001	4	5	5	Page 5	Grievances received 27 21\nAverage grievance resolution time 12 days 8 days\nPOSH complaints 1 0\nEmployee Assistance Programme (EAP) counselling was used by 58\nemployees. Wellness allowance utilisation: 71%.\n8. Major HR Initiatives in FY 2025–26\n1. Hybrid work model (3 office, 2 WFH) launched in June with\ninternet allowance of ₹1,500 per month.\n2. PeopleHub 2.0 went live in August, bringing leave, attendance,\nclaims, performance and grievances onto one platform.\n3. Revised benefits: Health cover raised from ₹4 lakh to ₹5 lakh;\nparental top-up option added.\n4. Leave policy update: Paternity leave increased to 10 days, EL\ncarry-forward cap increased to 30 days.\n5. Career framework: Published level guidelines (L1–L7) and dual\ncareer tracks in October.\n6. Women in Tech programme: Mentoring and returnship for 18\nparticipants.\n7. DPDP readiness: Employee privacy notice, retention schedule\nand data-access review completed.\n9. HR Budget\nItem Budget (₹ Actual (₹\nlakh) lakh)\nRecruitment 70 59\nTraining and development 133 112\nEngagement and events 40 43	f1a15f33ff38f0b4911b04e38cd96d4f3d051e12552d23c2de5955690d1ff594	gemini-embedding-2	indexed	2026-10-10 10:34:39.702866
99e39479-bf3d-4bd7-a23c-66415f889e0a	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ab5c26d1ac91	ver-4a758112	project-001	5	6	6	Page 6	HR technology (PeopleHub, tools) 55 58\nWellness and benefits 30 27\nadministration\nTotal 328 299\n10. Priorities for FY 2026–27\nPriority Target\nReduce voluntary Below 11.5%\nattrition\nHiring 90 net hires with 40% referral share\nLearning 40 hours per employee; 150 certifications\nEngagement Survey score 80%; eNPS +30\nDiversity 33% women in leadership roles (L4+) by\nMarch 2027\nCompensation Complete market benchmarking for\nengineering roles by September 2026\nAutomation Launch employee self-service chatbot for HR\nqueries on PeopleHub\nSuccession Identify successors for all L5 and above roles\n11. Conclusion\nNexora's people strategy supported business growth while improving\nhiring speed, engagement and learning. The focus for next year is\nretention in engineering, stronger career paths and further digitisation of\nHR services.\nAppendix: Detailed data tables are available from HR Analytics (hr-	9fbf85b54115cf5582aa8f6c686c1c3f3a6b6d0ef423420a4f7209020be50032	gemini-embedding-2	indexed	2026-10-10 10:34:40.50185
3694049f-9d68-4e57-a1d2-20162c18e404	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ab5c26d1ac91	ver-4a758112	project-001	6	7	7	Page 7	analytics@nexora-tech.example).	5ba6df08cc90e3a9ede5f66ee0cf209035b437b47e3b29b624009f8d9d3ad189	gemini-embedding-2	indexed	2026-10-10 10:34:41.417825
b7055c7f-fa1a-4d4b-9e10-09e7e02e8eb2	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-3d054e40aba7	ver-1564e40d	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nPerformance Review Guidelines\nDocument NXR-HR-GDL-005\nID\nVersion 3.0\nEffective 1 April 2026\nDate\nOwner Talent Management (Kavita Menon)\nApplies To All confirmed employees; probationers follow the\nprobation review in Section 9\n1. Purpose\nTo provide a fair, transparent and consistent method for evaluating\nperformance, giving feedback and linking outcomes to increments,\nbonuses and promotions.\n2. Review Cycle\nPhase Period Activity\nGoal setting 1 April – 30 Employee and manager agree 4–\nApril 6 goals in PeopleHub	45c3c336fe5117736ca9f12470bb4db7a1a78f2dde1554115de23a621a130b14	gemini-embedding-2	indexed	2026-10-10 10:34:44.400945
7ca3e2f5-e45c-43c6-8df4-c31845488a48	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-3d054e40aba7	ver-1564e40d	project-001	1	2	2	Page 2	Mid-year check-in 1 – 31 Progress review, goal\nOctober adjustment, development plan\nQuarterly 1:1s July, Informal feedback conversation\nJanuary\nSelf-assessment 1 – 10 Employee rates own performance\nMarch with evidence\nManager 11 – 20 Manager rates and writes\nassessment March comments\nCalibration 21 – 31 Department and HR calibration\nMarch sessions\nRating 1 – 10 April One-to-one feedback meeting\ncommunication\nIncrements and Effective 1 Paid with May salary\nbonus May\nThe appraisal year is April to March, aligned to the financial year.\n3. Evaluation Criteria\nEach employee is assessed on what was delivered (70%) and how it\nwas delivered (30%).\nComponent Weight Examples\nGoal achievement 50% Delivery against Atlas sprint\ncommitments, defect rates, client\nCSAT, revenue targets\nQuality and 20% Code review quality, documentation,\nownership on-call reliability\nCollaboration and 15% Teamwork across squads,\ncommunication stakeholder updates, mentoring\nNexora values 15% Integrity, Customer First,\nContinuous Learning, Ownership	f9039537dafac5898009186c8b36e625edf3d8f3b2c548d7ca34c075e6829a58	gemini-embedding-2	indexed	2026-10-10 10:34:45.019466
f6eddd55-744d-4c3a-8b05-f17ded522a75	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-3d054e40aba7	ver-1564e40d	project-001	2	3	3	Page 3	Managers (L4 and above) are also assessed on team engagement,\nattrition and talent development.\n4. Rating Scale\nRating Label Description Guidance\nDistribution\n5 Outstanding Exceptional impact About 5–8%\nbeyond role\n4 Exceeds Consistently above About 20–25%\nExpectations expectations\n3 Meets Fully meets role About 55–60%\nExpectations requirements\n2 Needs Partially meets; About 10–12%\nImprovement improvement plan\nneeded\n1 Unsatisfactory Does not meet Below 3%\nrequirements\nDistribution is a guide, not a forced curve. Departments with strong\nresults can justify a different spread during calibration.\n5. Manager Responsibilities\n• Set clear, measurable goals (SMART) within 30 days of the cycle\nstart.\n• Hold at least one structured 1:1 per month and document key\npoints in PeopleHub.\n• Collect peer feedback from at least 3 colleagues for each team\nmember (360-degree input for L3 and above).\n• Avoid recency bias by reviewing the full-year record, including\nsprint reports, client feedback and incident logs.	ccc7b203eec45467038bb24296ba9e6dd7ed96a0814ba4c2d9ae13010989e736	gemini-embedding-2	indexed	2026-10-10 10:34:45.857664
862f588d-8aa0-4291-b283-c71f320dd814	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-3d054e40aba7	ver-1564e40d	project-001	3	4	4	Page 4	• Communicate ratings in a face-to-face or video meeting with\nspecific examples.\n• Complete assessments by the deadline; late submissions are\nreported to the Department Head.\n6. Employee Responsibilities\n• Keep goals updated and record achievements with links (Jira\nepics, pull requests, client emails).\n• Request feedback proactively and complete the self-assessment\nhonestly.\n• Raise concerns about a rating through the Grievance Procedure\nwithin 15 days of the rating meeting.\n7. Impact on Compensation and Promotion\nRating Typical Annual Promotion Eligibility\nIncrement Bonus (% of\nRange target)\n5 12–18% 130% Fast-track nomination\n4 8–12% 110% Eligible\n3 5–8% 100% Eligible after tenure\ncriteria\n2 0–3% 50% Not eligible;\nimprovement plan\n1 0% 0% Not eligible;\nperformance\nimprovement plan (PIP)\nRanges are indicative and depend on company performance and budget\napproved by the Board.	38e9896c606843f777ed36c05ee317950d3e4d36799e4462d4174b3b6fa62d43	gemini-embedding-2	indexed	2026-10-10 10:34:46.680585
f6a0f219-deb0-4a12-8fb7-aa7346ff5090	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-3d054e40aba7	ver-1564e40d	project-001	4	5	5	Page 5	8. Performance Improvement Plan (PIP)\nEmployees rated 1, or rated 2 twice in a row, may be placed on a 60–90\nday PIP with documented targets, weekly check-ins and HR visibility.\nOutcomes: successful completion, extension (once, up to 30 days) or\nseparation.\n9. Probation Review\nNew joiners have reviews at 30, 60 and 90 days (180 days for L4+).\nConfirmation is by HR letter after a "Meets" or better review.\nExample: In FY 2025–26, Sneha (Senior Engineer, Project Meridian)\ndelivered the payment reconciliation module two sprints early, mentored\ntwo juniors and received strong client feedback. Her manager rated her\n4. She received a 10% increment effective 1 May 2026 and was\nnominated for promotion to Lead in the October cycle.	50c807d3a2116039324364301f26bebbbb8feed3d11caaa634e8fabb57e69f88	gemini-embedding-2	indexed	2026-10-10 10:34:47.270506
14038c37-bc4b-4f39-a4f4-b9dd0fa90e5e	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-d6402dc16e20	ver-1606e601	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nPromotion and Career Growth Guidelines\nDocument ID NXR-HR-GDL-012\nVersion 2.1\nEffective Date 1 April 2026\nOwner Talent Management (Kavita Menon)\nApplies To All confirmed employees\n1. Purpose\nTo describe the career levels at Nexora, the criteria for promotion, and\nthe review process so that employees understand how to grow and\nmanagers can make fair decisions.\n2. Career Levels\nLevel Engineering Title Typical Scope\nExperience\nL1 Associate 0–2 years Works on defined tasks\nEngineer with guidance	06de234df96a572146ab9833c319dd485b2e1d37b254d29cb93dabe6c201eb26	gemini-embedding-2	indexed	2026-10-10 10:34:50.737107
8850832e-8f3f-48b1-a58e-f6e2f58803f0	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-d6402dc16e20	ver-1606e601	project-001	1	2	2	Page 2	L2 Engineer 2–4 years Delivers features\nindependently\nL3 Senior Engineer 4–7 years Owns modules;\nmentors juniors\nL4 Lead Engineer 7–10 years Leads a squad; drives\ndesign and delivery\nL5 Principal Engineer 10–14 years Owns product area or\n/ Engineering multiple squads\nManager\nL6 Director 14+ years Owns a business unit\nor programme (for\nexample, Atlas)\nL7 VP / Head 18+ years Sets strategy across\nunits\nExperience is indicative. Promotion depends on demonstrated capability,\nnot years alone. Non-engineering functions (QA, Product, HR, Finance,\nSales) use the same levels with function-specific titles.\nThere are two growth tracks from L4: Technical (Principal,\nDistinguished Engineer) and Management (Manager, Director).\nEmployees may switch tracks once, with approval.\n3. Promotion Criteria\nCriterion What We Look For\nPerformance Rating of 4 or above in the last cycle and 3 or\nabove in the one before; no active warning or\nPIP\nMinimum tenure L1→L2: 18 months; L2→L3: 24 months; L3→L4:\nin level 30 months; L4→L5: 36 months\nReadiness at next Already performing at least 70% of the\nlevel responsibilities of the next level for 6 months	449d908712b75c7727acf7ce2ec44ed635355ed53d2ac802064f4cf16570485b	gemini-embedding-2	indexed	2026-10-10 10:34:51.40063
e3dfd61a-fef2-4c60-93ca-c785fe257e80	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-95f9bf76e643	ver-181767bd	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nTravel and Expense Policy\nDocument NXR-FIN-POL-013\nID\nVersion 3.0\nEffective 1 April 2026\nDate\nOwner Finance (Controller: Ramesh Patil) with Admin &\nTravel Desk\nApplies To All employees travelling on company business\n1. Purpose\nTo ensure business travel is approved, cost-effective and properly\ndocumented, and that reimbursements are fair and prompt.\n2. Business Travel Approval\nTravel Type Approver Lead Time\nDomestic, up to Reporting Manager 3 working days\n3 days	63fcb3b1899d3911f0e8b72191a00c132c857eb4a8ee426064b7105292c1fbd4	gemini-embedding-2	indexed	2026-10-10 10:35:13.456055
37572e95-6050-4a34-9d6b-45172cf891e1	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-d6402dc16e20	ver-1606e601	project-001	2	3	3	Page 3	Skills and Matches the competency framework (see\ncompetencies Section 4)\nBusiness need An open role or expanded scope exists;\npromotion is not automatic\nValues and Role-model behaviour and no conduct issues\nconduct\nFast-track: Employees rated 5 may be considered after half the\nminimum tenure, with Department Head and Head of HR approval\n(limited to 3% of headcount each cycle).\n4. Skills Expected by Level (Engineering\nExample)\nSkill Area L2 L3 L4 L5\nTechnical Strong in Deep in 2 Designs Defines\ndepth one stack areas systems architecture\nDelivery Completes Owns Leads Owns\nfeatures modules squad programme\nend to delivery outcomes\nend\nQuality Writes Improves Sets quality Drives\ntests code gates engineering\nstandards excellence\nCommunication Clear Presents Manages Influences\nupdates to clients stakeholders leadership\nMentoring Helps Mentors Coaches Builds\npeers 1–2 leads talent\njuniors pipeline\n5. Promotion Cycles and Review Process	e86f4881f919f54750c3444b5a8a3d461661cf7b982961a54d3a7253799a993b	gemini-embedding-2	indexed	2026-10-10 10:34:52.195484
f35ad0b4-7a74-497b-86ef-44f094630870	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-d6402dc16e20	ver-1606e601	project-001	3	4	4	Page 4	Cycle Nomination Panel Effective\nWindow Review Date\nApril cycle (with 1 – 31 March 1 – 15 April 1 May\nannual review)\nOctober cycle (mid- 1 – 15 1 – 15 1 November\nyear) September October\n1. Nomination: Manager submits a promotion case in PeopleHub\nwith achievements, impact examples and evidence of next-level\nperformance.\n2. Peer and stakeholder input: At least 3 reviewers (including a\nclient or cross-team stakeholder where relevant).\n3. Department review: Department Head endorses or rejects with\nreasons.\n4. Promotion panel: Head of HR, Head of Department and a leader\nfrom another function (for L3 and above also an independent\ntechnical reviewer) evaluate cases, using a standard scorecard.\n5. Decision: HR communicates outcome within 7 days; unsuccessful\ncandidates receive a development plan.\n6. Compensation: Promotion increment is 8–15% of fixed pay, with\na minimum of the entry salary for the new level.\n6. Career Development\n• Every employee has an Individual Development Plan (IDP) agreed\nat mid-year check-in.\n• Internal job postings are open to employees with 12+ months in\ncurrent role and rating 3 or above.\n• Cross-project rotation is possible after 18 months, with manager\nand HR approval.\n• Career conversations with manager at least twice a year.\nExample: Rahul (Senior Engineer, L3, 3 years in level) has rated 4 in\nFY 2025–26 and 3 the year before. He led the Atlas notification service\nredesign and now mentors two juniors. His manager nominates him in\nthe March window with three stakeholder reviews. The panel approves	c691c5541f892d8120f9e7cf795214dc62b7a79a864a6d5fe03fc0ed1a3a53d6	gemini-embedding-2	indexed	2026-10-10 10:34:52.799795
ea599a71-931a-4fb6-b1e8-060bc951888d	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-d6402dc16e20	ver-1606e601	project-001	4	5	5	Page 5	his promotion to Lead Engineer (L4), effective 1 May 2026 with a 12%\nincrement.\n7. Appeals\nEmployees not selected can ask for feedback within 7 days and may\nraise a grievance under NXR-HR-PRC-010 if they believe the process\nwas unfair.	1f54b0ebe86397c647f8c9b4ddc85aba0325777a785f042e0a4783b7f93edd91	gemini-embedding-2	indexed	2026-10-10 10:34:53.582733
4aad2ce0-6ac7-40a8-8034-00b6c01a575a	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-cf0975b45d02	ver-137ad6fc	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nRemote Work Security Guidelines\nDocument NXR-IT-GDL-008\nID\nVersion 2.5\nEffective 1 April 2026\nDate\nOwner Information Security Office (CISO: Dr. Farhan\nQureshi)\nApplies To All employees, contractors and interns working\noutside Nexora offices\n1. Purpose\nTo protect Nexora and client data when employees work from home,\nclient sites, travel or any non-office location. These guidelines support\nISO 27001 requirements and client security clauses (for example, those\nin the Project Meridian banking contract).\n2. VPN Usage\n• Connect to the Nexora VPN (GlobalProtect) before accessing\nany internal system, code repository, staging environment or client	2a12ef6263956ffb3c58871d0b764f89aebaa352144ea6c7d4e3472ada0cd04d	gemini-embedding-2	indexed	2026-10-10 10:34:58.37191
6ad2ad64-4d14-4122-9c8f-20074616f620	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-cf0975b45d02	ver-137ad6fc	project-001	1	2	2	Page 2	network.\n• VPN must stay connected for the whole working session. Auto-\ndisconnect after 30 minutes of inactivity is enforced.\n• Do not share VPN credentials or install other VPN or proxy\nsoftware on company laptops.\n• Split tunnelling is disabled for engineers with access to client\nproduction data.\n• If VPN is not working, raise a P2 ticket on ServiceDesk. Do not\nuse workarounds such as personal email or personal cloud\nstorage.\n3. Password and Authentication Rules\nRule Requirement\nMinimum length 14 characters (passphrase recommended)\nComplexity Upper, lower, number and symbol, or four\nrandom words\nChange frequency Every 180 days, or immediately if\ncompromise is suspected\nReuse Never reuse any of the last 10 passwords or\npersonal-account passwords\nMulti-factor Mandatory for email, VPN, cloud consoles,\nauthentication (MFA) GitHub and PeopleHub\nPassword manager Use the company-approved vault; do not\nstore passwords in browsers, notes or chat\nSharing Never share passwords, MFA codes or\nOTPs, even with IT staff\n4. Device Protection\nControl Requirement	dcd64157c685196da1b8299bbefbc2ece3c2cf4eef8104ab64b0f9398e67c933	gemini-embedding-2	indexed	2026-10-10 10:34:59.011427
67416f87-a274-4b25-908f-85d3a5392b36	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-cf0975b45d02	ver-137ad6fc	project-001	2	3	3	Page 3	Device Use only the Nexora-issued laptop for work; no\npersonal devices for code or client data\nDisk encryption BitLocker or FileVault enabled (checked\nautomatically)\nEndpoint security Antivirus/EDR agent must be active; do not\ndisable or uninstall\nUpdates Install OS and security updates within 7 days of\nrelease\nScreen lock Auto-lock after 5 minutes; lock manually when\nleaving the desk\nPhysical security Do not leave laptops in cars or unattended in\npublic places\nUSB and external Blocked by default; exceptions need CISO\nstorage approval\nSoftware Install only from the company software catalogue\nFamily and Do not let others use the work laptop or view\nguests client information\nLost or stolen devices must be reported to security@nexora-\ntech.example and ServiceDesk within 2 hours. The device is remotely\nlocked and wiped.\n5. Public Wi-Fi and Network Rules\n• Do not use public Wi-Fi (cafés, airports, hotels) for work unless\nVPN is connected first.\n• Prefer a mobile hotspot over unknown networks.\n• Home Wi-Fi: use WPA2/WPA3 encryption, change the default\nrouter admin password, and keep router firmware updated.\n• Do not join networks asking for installation of certificates or apps.\n• Avoid confidential calls in public places; use headphones and\nprivacy screens when travelling.	7fcd5afcb7e0ead88f2db237fdbaa5ca9fade81ab7cd1350a4ce51fed57cedf3	gemini-embedding-2	indexed	2026-10-10 10:34:59.5767
e4362db5-4ce6-4ab8-af65-10915af90f57	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-cf0975b45d02	ver-137ad6fc	project-001	3	4	4	Page 4	6. Data Handling\nData Class Examples Handling Rule\nPublic Marketing material No restriction\nInternal Policies, project Share only within Nexora\nplans\nConfidential Source code, Store in approved SharePoint/\ncustomer lists, GitHub; no personal email or\ncontracts messaging apps\nRestricted Client PII, financial Access on need-to-know basis;\nand payment data, encryption in transit and at\ncredentials rest; no local download\n• Do not copy client data to personal drives, USB, or AI tools that\nare not approved by Nexora.\n• Print only when necessary and shred documents after use.\n• Take screenshots and photos of screens only with permission.\n• Follow the data retention rules in the Employee Data Management\nProcedure (NXR-HR-PRC-014).\n7. Phishing and Incident Reporting\n• Verify unexpected links, attachments and payment or credential\nrequests. Use the Report Phishing button in Outlook.\n• Report any suspected incident (malware, data leak, wrong-\nrecipient email) to the Security Operations Centre immediately via\nsecurity@nexora-tech.example or the 24×7 line,\n+91-20-5550-0199.\n• Do not attempt to investigate or delete evidence yourself.\n• Quarterly phishing simulations are run. Repeated failures lead to\nrefresher training.\nExample: Ananya receives an email that looks like it comes from the\nAtlas client's finance lead asking for a payment API key. She notices the	4335dc944c8944ce08d8ec40cef49640a2cd0a24784bb0978fffdd52531eabba	gemini-embedding-2	indexed	2026-10-10 10:35:00.172079
1d743b61-1994-442d-a74d-532bfe0e2dff	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-cf0975b45d02	ver-137ad6fc	project-001	4	5	5	Page 5	sender domain is slightly misspelled, clicks Report Phishing, and\ninforms the SOC. The domain is blocked within 20 minutes.\n8. Compliance\nAnnual security training and a quarterly self-attestation are mandatory.\nViolations may lead to access suspension and disciplinary action under\nthe Code of Employee Conduct.	68a2ce609432c6343cbd018fdad6af362ae9e20b76d562e09030c7fdfef304b3	gemini-embedding-2	indexed	2026-10-10 10:35:01.078923
8a2e806a-999c-4d62-93a7-79144384d58c	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-95f9bf76e643	ver-181767bd	project-001	1	2	2	Page 2	Domestic, more Manager + Department Head 5 working days\nthan 3 days\nInternational Department Head + Finance 15 working days\nController; CFO approval for (visa and\nL5 and above booking)\nClient-mandated Manager (client email As per client\ntravel attached) need\nRaise a request on PeopleHub → Travel. Bookings are made only\nthrough the Nexora Travel Desk (travel@nexora-tech.example) or the\napproved booking tool. Non-approved travel is not reimbursed.\n3. Transportation\nMode Entitlement\nAir (domestic) Economy class; book at least 7 days ahead; lowest\nlogical fare\nAir Economy; Premium Economy for flights over 8\n(international) hours, L5 and above\nTrain AC 2-tier (L1–L4); AC 1st class or Executive Chair\n(L5+)\nLocal travel Metro/bus or app-based cab (Mini/Sedan); auto-\nrickshaw for short distance\nPersonal car ₹12 per km; bike ₹5 per km, with a log of distance,\npurpose and parking/toll bills\nAirport Cab as per local travel rules\ntransfers\nCancellation charges resulting from a personal reason are borne by the\nemployee.	e250779a35eee4ae57948334e9eb748f105c21cae27c2d57d878aa0e50304679	gemini-embedding-2	indexed	2026-10-10 10:35:14.066283
7fd566e4-1151-43ec-b7b3-5546019a18d2	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-95f9bf76e643	ver-181767bd	project-001	2	3	3	Page 3	4. Accommodation\nCity Tier L1–L3 L4–L5 L6 and\nabove\nTier 1 (Mumbai, Delhi NCR, ₹5,500 ₹7,500 ₹10,000\nBengaluru, Hyderabad, Pune, per night\nChennai)\nTier 2 (Ahmedabad, Jaipur, Kochi, ₹4,000 ₹5,500 ₹7,500\netc.)\nInternational Up to $200 $300\n$150\nHotels should be on the approved list where possible. Stay with friends\nor family is not reimbursed. Laundry is allowed for stays of 4 or more\nnights up to ₹500.\n5. Meals and Daily Allowance (Per Diem)\nLocation Daily Meal Breakdown\nLimit\nTier 1 city ₹1,200 Breakfast ₹250, Lunch ₹400, Dinner\n₹550\nTier 2 / ₹900 Breakfast ₹200, Lunch ₹300, Dinner\nother ₹400\nInternational $45 As per country guide\nAlcohol is not reimbursable. Client entertainment up to ₹2,500 per\nperson needs pre-approval and must list attendees and purpose.\n6. Other Eligible Expenses	be01da4a0a68a6600e4f0ceee7c43c9503f8c4096325c6a754e5bc48099b3254	gemini-embedding-2	indexed	2026-10-10 10:35:14.893493
e02b41ae-c8f0-4d5e-ab41-d72d690346e5	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-95f9bf76e643	ver-181767bd	project-001	3	4	4	Page 4	Visa and travel insurance (international), airport lounge (only if included\nin card/ticket), Wi-Fi/data when travelling (up to ₹500 per trip), and\nparking and toll charges. Not eligible: fines, personal shopping, mini-\nbar, in-room entertainment, personal phone calls, or upgrades without\napproval.\n7. Advances\nUp to 75% of estimated cost can be requested 5 working days before\ntravel. Unused advance must be returned or settled within 10 days of\nreturn.\n8. Reimbursement Process\n1. File the expense report on PeopleHub → Expenses within 15\ndays of return (claims after 45 days are rejected).\n2. Attach original receipts for each item above ₹300; GST invoices in\nthe company name where available.\n3. Manager approves within 3 working days.\n4. Finance validates policy compliance and pays within 7 working\ndays of approval with the next payroll or by bank transfer.\n5. Exceptions (over-limit spending) need Department Head approval\nbefore the trip.\nExample: Sameer (Lead Engineer, L4) travels from Pune to Bengaluru\non 12–14 August for a Meridian client workshop. Approved by manager\nand Department Head. Economy flight ₹5,800; hotel 2 nights at ₹7,200\nper night; meals 3 days at ₹1,000 per day; cabs ₹1,350. Total ₹24,550.\nHe files the claim on 18 August with receipts, and Finance reimburses it\non 28 August.\n9. Compliance	8c78a46bd197626b48c18df5995f4eede8548db98f9564b45aac6e5288f5e885	gemini-embedding-2	indexed	2026-10-10 10:35:15.705297
c1c043a3-1925-4584-b481-e1de54e79ebc	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-95f9bf76e643	ver-181767bd	project-001	4	5	5	Page 5	False claims, duplicate claims or altered bills are violations of the Code\nof Employee Conduct. Finance conducts random audits of 10% of claims\neach quarter.	52b601bcd767d1db5f4795512fe123d37b01c7701ef45f2ee009020c154367a5	gemini-embedding-2	indexed	2026-10-10 10:35:16.538274
1f6b259f-680f-4b0f-ae46-455acf767b6b	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-f5e24b39a009	ver-0e690a3b	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nWork From Home (Hybrid Work) Policy\nDocument ID NXR-HR-POL-003\nVersion 2.1\nEffective Date 1 April 2026\nOwner Head of HR with CTO (Sanjay Kulkarni)\nApplies To Eligible employees in India offices\n1. Purpose\nNexora follows a hybrid model: three days in office and two days from\nhome each week. This policy explains who can work from home (WFH),\nhow to request it, expected working hours, equipment support and\nproductivity expectations.\n2. Eligibility\nCategory Eligibility\nConfirmed employees (all levels) Standard hybrid: 2 WFH\ndays per week	e369c1f834f643495ff65db29e6d2f57c7fe208944c1766845771b3c14994dd7	gemini-embedding-2	indexed	2026-10-10 10:35:23.607029
6f1a949e-321b-4d37-accb-4f095766d45a	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-f5e24b39a009	ver-0e690a3b	project-001	1	2	2	Page 2	Employees on probation Up to 1 WFH day per week,\nwith manager approval\nInterns and trainees Office-based; WFH only for\nexceptions\nRoles needing physical presence (IT Not eligible unless\nAdmin, Facilities, Hardware Lab, approved by HR\nReception)\nFully remote roles Only if stated in offer letter\n(currently 14 employees)\nWFH is a facility, not an entitlement, and may be withdrawn for\nperformance or conduct reasons after written notice.\n3. Approval Process\n1. Standard hybrid days: Teams agree a fixed anchor day in office\n(for example, Tuesday and Thursday for Project Atlas squads). No\nper-day approval is needed.\n2. Extra WFH days (up to 10 per year): Request in PeopleHub at\nleast 1 working day ahead. Manager approves.\n3. Extended WFH (more than 2 weeks, for example, medical or\nrelocation): Written request to manager and HR Business\nPartner. Maximum 8 weeks, renewable once.\n4. Working from another city or state: Needs HR and IT Security\napproval for tax, labour-law and data-security reasons.\n5. Working from outside India: Not permitted without Legal, HR\nand Finance approval.\n4. Working Hours and Availability\n• Be available online 11:00 AM – 4:00 PM (core hours) on WFH\ndays; total working hours remain 8.\n• Mark attendance on PeopleHub Mobile at start and end of day.	1e8d60e08b0cdd4b1ed394a311124462de4f8238e3b6c610458d0dd8ab1bbecc	gemini-embedding-2	indexed	2026-10-10 10:35:24.162142
da6a5c14-9216-43b3-b0ec-a21f313c3520	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-fc174a6d	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Onboarding Procedure\nDocument NXR-HR-PRC-006\nID\nVersion 2.3\nEffective 1 April 2026\nDate\nOwner HR Operations (Rahul Deshmukh)\nApplies To All new joiners (full-time employees, interns, fixed-\nterm staff)\n1. Purpose\nTo give every new joiner a smooth, compliant and welcoming start, and\nto ensure accounts, equipment, training and documents are ready by\nDay 1.\n2. Roles and Responsibilities\nRole Responsibility\nHR Operations Offer paperwork, document verification, induction\nschedule	869b1f7b99a771fb8d6ed9d37c221e601529bcd2b719d3d3ecb8c135504e39e0	gemini-embedding-2	indexed	2026-10-10 11:02:58.840015
da24c57b-18f5-471c-93af-e028fe9ff895	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-f5e24b39a009	ver-0e690a3b	project-001	2	3	3	Page 3	• Keep Microsoft Teams status current and respond to messages\nwithin 30 minutes during core hours.\n• Attend all scheduled stand-ups and client calls with camera on,\nunless the meeting owner says otherwise.\n• Out-of-hours work is not expected. Overtime rules in the\nAttendance Policy apply.\n5. Equipment and Allowances\nItem Support Provided\nLaptop Company-issued; only this device may be used\nfor work\nMonitor, keyboard, Collect from office or claim one-time\nmouse reimbursement\nDesk and chair One-time ₹10,000 (once every 3 years, bills\nsetup required)\nInternet and ₹1,500 per month, paid with salary for\nelectricity employees on regular hybrid\nHeadset One company-provided headset on request\nTechnical issues Raise a ticket on ServiceDesk; remote support\nwithin 4 working hours\nEmployees must keep a stable internet connection (at least 25 Mbps\nrecommended) and a quiet workspace for calls. Company equipment\nmust be used as per the Remote Work Security Guidelines (NXR-HR-\nPOL-008).\n6. Productivity Expectations\n• Goals and deliverables are tracked through Jira sprints and\nweekly 1:1s. Output matters more than hours online.\n• Teams run a daily 15-minute stand-up and a weekly planning	3e86f642ad72d61faf297d88b0eb82ba03c3cfdcf28e91dd248364d0a02cbfc5	gemini-embedding-2	indexed	2026-10-10 10:35:24.947323
27882ece-3482-4362-9882-585c4e4f585b	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-f5e24b39a009	ver-0e690a3b	project-001	3	4	4	Page 4	session.\n• If sprint commitments are repeatedly missed or a person is\nunreachable during core hours, the manager may reduce WFH\ndays after discussion and a written note to HR.\n• Client contracts that mandate on-site presence (for example, the\nMeridian programme for a banking client) override this policy for\nnamed team members.\nExample: Neha (Engineer, L2) is on the Atlas payments squad. Her\nsquad's anchor days are Tuesday and Wednesday, and she chooses\nThursday as her third office day. She works from home on Monday and\nFriday. If she wants to work from home on Thursday as well, she raises\nan extra WFH request in PeopleHub one working day ahead, and it\ncounts towards her 10 extra days for the year.\n7. Health and Safety\nEmployees are responsible for a safe, ergonomic workspace. Injuries\noccurring during working hours at home should be reported to HR within\n24 hours.\n8. Policy Review\nThe policy is reviewed annually in March. Feedback can be sent to\nhr@nexora-tech.example.	9be6bd53b70e00eadd59486033719eef6f0df961540d8ca56e94f5fbc1054983	gemini-embedding-2	indexed	2026-10-10 10:35:25.581516
82c46877-592b-4233-9c08-54cd74762def	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ff2f2247df35	ver-4f6493e3	project-001	0	1	1	General Overview	Google Drive Document: folder_123\nFile ID: 1Da7uW8AFK094o2_7ctNX5nqwwOWNNJRy\nContent synchronized from Google Drive source link.	cdb58b8b9f6e4a0996ba232603e181657aee78a5577cf8576077db4762bb05e4	gemini-embedding-2	indexed	2026-10-10 11:02:20.509586
4018b3bc-b222-4176-9693-a39493d2e845	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ff2f2247df35	ver-8ca16edf	project-001	0	1	1	General Overview	Google Drive Document: folder_123\nFile ID: 1Da7uW8AFK094o2_7ctNX5nqwwOWNNJRy\nContent synchronized from Google Drive source link.	cdb58b8b9f6e4a0996ba232603e181657aee78a5577cf8576077db4762bb05e4	gemini-embedding-2	indexed	2026-10-10 11:02:20.512193
9d399291-bad9-4091-8882-4fdaca62605a	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ff2f2247df35	ver-e28499e6	project-001	0	1	1	General Overview	Google Drive Document: folder_123\nFile ID: 1Da7uW8AFK094o2_7ctNX5nqwwOWNNJRy\nContent synchronized from Google Drive source link.	cdb58b8b9f6e4a0996ba232603e181657aee78a5577cf8576077db4762bb05e4	gemini-embedding-2	indexed	2026-10-10 11:02:20.510595
b666872b-7d6a-416f-a6d9-3a4361fb761b	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ff2f2247df35	ver-a57fa3f0	project-001	0	1	1	General Overview	Google Drive Document: folder_123\nFile ID: 1Da7uW8AFK094o2_7ctNX5nqwwOWNNJRy\nContent synchronized from Google Drive source link.	cdb58b8b9f6e4a0996ba232603e181657aee78a5577cf8576077db4762bb05e4	gemini-embedding-2	indexed	2026-10-10 11:02:20.511648
4d73cacf-45ea-40d2-89ef-d88b64953591	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ff2f2247df35	ver-558ec618	project-001	0	1	1	General Overview	Google Drive Document: folder_123\nFile ID: 1Da7uW8AFK094o2_7ctNX5nqwwOWNNJRy\nContent synchronized from Google Drive source link.	cdb58b8b9f6e4a0996ba232603e181657aee78a5577cf8576077db4762bb05e4	gemini-embedding-2	indexed	2026-10-10 11:02:20.507951
24d03420-bcb2-4442-b468-bb77a4f17792	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-ff2f2247df35	ver-f4d346f5	project-001	0	1	1	General Overview	Google Drive Document: folder_123\nFile ID: 1Da7uW8AFK094o2_7ctNX5nqwwOWNNJRy\nContent synchronized from Google Drive source link.	cdb58b8b9f6e4a0996ba232603e181657aee78a5577cf8576077db4762bb05e4	gemini-embedding-2	indexed	2026-10-10 11:02:20.503961
ff2adec0-0318-4b26-930d-2c4346bc4978	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-50690e9459bb	ver-1cb0bac9	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nCode of Employee Conduct\nDocument ID NXR-HR-POL-009\nVersion 3.1\nEffective 1 April 2026\nDate\nOwner Head of HR with Legal & Compliance (Adv. Pooja\nNair)\nApplies To All employees, interns, contractors and consultants\n1. Our Values\nIntegrity. Customer First. Continuous Learning. Ownership.\nRespect. This Code explains how we apply these values every day.\n2. Workplace Behaviour\n• Treat colleagues, clients and vendors with courtesy, regardless of\nrole, gender, religion, caste, age, disability, sexual orientation,\nnationality or background.\n• Communicate professionally in meetings, Teams chats, emails\nand code reviews. Constructive disagreement is welcome;\npersonal attacks are not.	570119aa9564264a1b3117aa44f987ccd4c3d7ac35be47295f865c6d3de7251b	gemini-embedding-2	indexed	2026-10-10 11:02:30.045478
edac2061-ce00-4d29-9d4e-866bfa5fb9ba	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-50690e9459bb	ver-1cb0bac9	project-001	1	2	2	Page 2	• Be punctual, prepared and reliable. Keep commitments made to\nteammates and clients.\n• Dress code is business casual; client-facing days follow client site\nrules.\n• Alcohol, tobacco and illegal substances are not allowed on\ncompany premises or at company events held on premises.\n• Use company resources (laptop, internet, licences) primarily for\nbusiness.\n3. Ethics and Integrity\n• Be honest in reports, timesheets, expense claims and client\ncommunication.\n• Do not accept or offer bribes, kickbacks or improper benefits.\nGifts from vendors or clients above ₹3,000 in value must be\ndeclared to your manager and the Compliance team and may\nneed to be returned.\n• Respect intellectual property. Do not use pirated software or copy\ncode or content without licence.\n• Protect confidential information about Nexora, its clients and\ncolleagues during and after employment.\n• Follow all applicable laws, including anti-corruption, data\nprotection and labour laws.\n• Whistleblower protection: Concerns about fraud, financial\nmisreporting or serious misconduct can be raised confidentially at\nethics@nexora-tech.example. Retaliation against anyone who\nreports in good faith is prohibited.\n4. Conflicts of Interest\nA conflict arises when personal interests could influence, or appear to\ninfluence, your work decisions.\nSituation Rule	b231ed22ffb0b9c1c9fec20a0da2269543797961616a06188b756f75ace22895	gemini-embedding-2	indexed	2026-10-10 11:02:30.700006
3bf90640-1a6c-44e3-a26e-bd9cde6b7ee7	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-50690e9459bb	ver-1cb0bac9	project-001	2	3	3	Page 3	Outside employment or Needs prior written approval; not\nfreelancing allowed with competitors or clients\nInvestment in vendors, Declare if holding more than 2% or any\nclients or competitors role in management\nRelatives working at Declare at joining; no direct reporting or\nNexora hiring influence over relatives\nHiring or buying from Must be declared and approved by the\nrelatives' firms Head of Compliance\nBoard or advisory positions Needs CEO approval\nelsewhere\nEmployees complete an annual conflict-of-interest declaration in\nPeopleHub by 30 April.\n5. Prevention of Sexual Harassment (POSH)\nNexora has zero tolerance for sexual harassment, as defined by the\nSexual Harassment of Women at Workplace (Prevention, Prohibition\nand Redressal) Act, 2013, and extends the same standards to all\ngenders in this policy.\n• Prohibited conduct includes unwelcome physical contact, sexual\nremarks, jokes, messages, showing explicit material, and stalking.\n• Complaints may be made in writing to the Internal Committee\n(IC) at ic@nexora-tech.example within 3 months of the incident\n(extendable by 3 months).\n• The IC is chaired by a senior woman employee (Kavita Menon)\nwith an external member from an NGO.\n• Inquiry is completed within 90 days; confidentiality is maintained\nfor all parties.\n• Interim measures such as a change in reporting line or leave may\nbe offered during inquiry.\n6. Other Prohibited Conduct	b3b5a1cebf568a1f32fa8bb3cc81c98a9dc9ceee924fc00a027c9780c72e2655	gemini-embedding-2	indexed	2026-10-10 11:02:31.494925
f0f09271-cd07-45a8-8afc-b8e5ed157348	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-50690e9459bb	ver-1cb0bac9	project-001	3	4	4	Page 4	Bullying, discrimination, violence or threats; theft or fraud; deliberate\ndamage to company property; sharing client or company data without\nauthorisation; use of social media to disclose confidential information or\ndisparage the company; and retaliation against complainants.\n7. Disciplinary Actions\nLevel Examples Possible Action\nMinor Repeated lateness, minor Verbal counselling or\npolicy breaches written warning\nModerate Misuse of resources, Final written warning;\nunprofessional behaviour, withholding increment\nfailure to disclose a conflict or bonus\nSerious Harassment, data leak, falsified Suspension,\nrecords, fraud, violence, termination, and legal\nrepeated moderate offences action where required\nProcess: (1) Allegation reported to HR; (2) Show-cause notice with 3\nworking days to reply; (3) Fact-finding by HR with Legal; (4) Decision\ncommunicated in writing within 15 working days; (5) Appeal to the Head\nof HR within 7 days of the decision.\nExample: An employee on Project Beacon is found to have submitted a\nfake taxi bill for ₹2,400. HR issues a show-cause notice, the employee\nadmits the error, repays the amount, and receives a final written\nwarning. A repeat would lead to termination.\n8. Acknowledgement\nEvery employee signs this Code at joining and acknowledges updates\nannually through PeopleHub.	71fd77dd106080c81c62035c29b28b40aa4cce653a31af6066201642fd408e27	gemini-embedding-2	indexed	2026-10-10 11:02:32.286042
d9a66300-d0b9-4ba4-b806-e4e6b626a2fd	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-50690e9459bb	ver-900162b3	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nCode of Employee Conduct\nDocument ID NXR-HR-POL-009\nVersion 3.1\nEffective 1 April 2026\nDate\nOwner Head of HR with Legal & Compliance (Adv. Pooja\nNair)\nApplies To All employees, interns, contractors and consultants\n1. Our Values\nIntegrity. Customer First. Continuous Learning. Ownership.\nRespect. This Code explains how we apply these values every day.\n2. Workplace Behaviour\n• Treat colleagues, clients and vendors with courtesy, regardless of\nrole, gender, religion, caste, age, disability, sexual orientation,\nnationality or background.\n• Communicate professionally in meetings, Teams chats, emails\nand code reviews. Constructive disagreement is welcome;\npersonal attacks are not.	570119aa9564264a1b3117aa44f987ccd4c3d7ac35be47295f865c6d3de7251b	gemini-embedding-2	indexed	2026-10-10 11:02:30.677971
03553e3c-6bc2-45a7-9a42-9add9bd30894	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-50690e9459bb	ver-900162b3	project-001	1	2	2	Page 2	• Be punctual, prepared and reliable. Keep commitments made to\nteammates and clients.\n• Dress code is business casual; client-facing days follow client site\nrules.\n• Alcohol, tobacco and illegal substances are not allowed on\ncompany premises or at company events held on premises.\n• Use company resources (laptop, internet, licences) primarily for\nbusiness.\n3. Ethics and Integrity\n• Be honest in reports, timesheets, expense claims and client\ncommunication.\n• Do not accept or offer bribes, kickbacks or improper benefits.\nGifts from vendors or clients above ₹3,000 in value must be\ndeclared to your manager and the Compliance team and may\nneed to be returned.\n• Respect intellectual property. Do not use pirated software or copy\ncode or content without licence.\n• Protect confidential information about Nexora, its clients and\ncolleagues during and after employment.\n• Follow all applicable laws, including anti-corruption, data\nprotection and labour laws.\n• Whistleblower protection: Concerns about fraud, financial\nmisreporting or serious misconduct can be raised confidentially at\nethics@nexora-tech.example. Retaliation against anyone who\nreports in good faith is prohibited.\n4. Conflicts of Interest\nA conflict arises when personal interests could influence, or appear to\ninfluence, your work decisions.\nSituation Rule	b231ed22ffb0b9c1c9fec20a0da2269543797961616a06188b756f75ace22895	gemini-embedding-2	indexed	2026-10-10 11:02:31.687348
edc58eb4-9863-45e7-9f96-6f0235660feb	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-50690e9459bb	ver-900162b3	project-001	2	3	3	Page 3	Outside employment or Needs prior written approval; not\nfreelancing allowed with competitors or clients\nInvestment in vendors, Declare if holding more than 2% or any\nclients or competitors role in management\nRelatives working at Declare at joining; no direct reporting or\nNexora hiring influence over relatives\nHiring or buying from Must be declared and approved by the\nrelatives' firms Head of Compliance\nBoard or advisory positions Needs CEO approval\nelsewhere\nEmployees complete an annual conflict-of-interest declaration in\nPeopleHub by 30 April.\n5. Prevention of Sexual Harassment (POSH)\nNexora has zero tolerance for sexual harassment, as defined by the\nSexual Harassment of Women at Workplace (Prevention, Prohibition\nand Redressal) Act, 2013, and extends the same standards to all\ngenders in this policy.\n• Prohibited conduct includes unwelcome physical contact, sexual\nremarks, jokes, messages, showing explicit material, and stalking.\n• Complaints may be made in writing to the Internal Committee\n(IC) at ic@nexora-tech.example within 3 months of the incident\n(extendable by 3 months).\n• The IC is chaired by a senior woman employee (Kavita Menon)\nwith an external member from an NGO.\n• Inquiry is completed within 90 days; confidentiality is maintained\nfor all parties.\n• Interim measures such as a change in reporting line or leave may\nbe offered during inquiry.\n6. Other Prohibited Conduct	b3b5a1cebf568a1f32fa8bb3cc81c98a9dc9ceee924fc00a027c9780c72e2655	gemini-embedding-2	indexed	2026-10-10 11:02:32.28023
61de4998-c9d1-4ede-9aac-9b1dd52bdba8	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-50690e9459bb	ver-900162b3	project-001	3	4	4	Page 4	Bullying, discrimination, violence or threats; theft or fraud; deliberate\ndamage to company property; sharing client or company data without\nauthorisation; use of social media to disclose confidential information or\ndisparage the company; and retaliation against complainants.\n7. Disciplinary Actions\nLevel Examples Possible Action\nMinor Repeated lateness, minor Verbal counselling or\npolicy breaches written warning\nModerate Misuse of resources, Final written warning;\nunprofessional behaviour, withholding increment\nfailure to disclose a conflict or bonus\nSerious Harassment, data leak, falsified Suspension,\nrecords, fraud, violence, termination, and legal\nrepeated moderate offences action where required\nProcess: (1) Allegation reported to HR; (2) Show-cause notice with 3\nworking days to reply; (3) Fact-finding by HR with Legal; (4) Decision\ncommunicated in writing within 15 working days; (5) Appeal to the Head\nof HR within 7 days of the decision.\nExample: An employee on Project Beacon is found to have submitted a\nfake taxi bill for ₹2,400. HR issues a show-cause notice, the employee\nadmits the error, repays the amount, and receives a final written\nwarning. A repeat would lead to termination.\n8. Acknowledgement\nEvery employee signs this Code at joining and acknowledges updates\nannually through PeopleHub.	71fd77dd106080c81c62035c29b28b40aa4cce653a31af6066201642fd408e27	gemini-embedding-2	indexed	2026-10-10 11:02:32.891647
0bc6fc6c-1b4a-4b1f-9943-8ef0f6045e7b	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-e839e80c	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Onboarding Procedure\nDocument NXR-HR-PRC-006\nID\nVersion 2.3\nEffective 1 April 2026\nDate\nOwner HR Operations (Rahul Deshmukh)\nApplies To All new joiners (full-time employees, interns, fixed-\nterm staff)\n1. Purpose\nTo give every new joiner a smooth, compliant and welcoming start, and\nto ensure accounts, equipment, training and documents are ready by\nDay 1.\n2. Roles and Responsibilities\nRole Responsibility\nHR Operations Offer paperwork, document verification, induction\nschedule	869b1f7b99a771fb8d6ed9d37c221e601529bcd2b719d3d3ecb8c135504e39e0	gemini-embedding-2	indexed	2026-10-10 11:03:00.406083
71914502-b2d1-4611-bd18-7105f16a2181	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-e839e80c	project-001	1	2	2	Page 2	Hiring Manager Buddy assignment, 30-60-90 day plan, project\nintroduction\nIT Service Desk Laptop, accounts, access, security briefing\nAdmin & Access card, desk, parking, ID card\nFacilities\nFinance & Salary setup, PF/UAN, bank details\nPayroll\nOnboarding Day-to-day guide for the first 30 days\nBuddy\n3. Pre-Joining (Offer Accepted to Day -1)\nTimeline Action Owner\nOffer Welcome email with joining checklist HR\nacceptance\nT-10 days Background verification (BGV) initiated HR\nthrough third-party agency\nT-7 days Laptop and accessories requested on Manager\nServiceDesk\nT-5 days Buddy assigned; team informed Manager\nT-3 days Email ID and Teams account created IT\n(not yet activated)\nT-1 day Reminder call; confirm reporting time and HR\nlocation\n4. Document Verification\nOriginals must be shown on Day 1; copies are retained.	df84c8a9b6595201384b4269be33d53526d8e7f8be798b6c33b18cb9b79ba24d	gemini-embedding-2	indexed	2026-10-10 11:03:01.171234
2829430c-d772-4428-861e-eaebb139f31c	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-e839e80c	project-001	2	3	3	Page 3	Category Documents\nIdentity Aadhaar, PAN (mandatory), passport (if available)\nAddress Aadhaar or utility bill / rental agreement\nEducation Degree and mark sheets (highest qualification\nmandatory)\nEmployment Relieving letter, last 3 payslips, experience letters from\nprevious employers\nFinancial Cancelled cheque or bank statement, UAN number\nOther 4 passport photographs, medical fitness (for night-shift\nroles)\nIf documents are pending, HR may allow up to 7 working days to\nsubmit, with manager approval. Joining may be withdrawn if BGV finds\nmaterial discrepancies.\n5. Account and Access Creation\nSystem Provided Ready By\nBy\nCompany email and Microsoft IT Day 1, 10:00 AM\nTeams\nPeopleHub (HRMS) HR Day 1\nVPN and multi-factor IT Day 1\nauthentication\nJira, Confluence, GitHub Project Day 2\nEnterprise Admin\nProject-specific environments (for Project Day 3, after\nexample, Atlas staging) Lead security training\nServiceDesk IT Day 1\nAccess follows the least privilege principle. Production access is	632360447a2ef22a637e043d6a3d59225fb3de42a9718e1057c58886434b3881	gemini-embedding-2	indexed	2026-10-10 11:03:01.982658
319b4848-e9eb-438a-87d3-ce76b8d02928	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-e839e80c	project-001	3	4	4	Page 4	granted only after 30 days and manager approval.\n6. Induction and Training\nDay Session\nDay 1 Welcome, company overview, HR policies, benefits\nwalkthrough\nDay 2 Information security and Remote Work Security training\n(mandatory, assessed)\nDay 3 POSH and Code of Conduct awareness (e-learning)\nWeek 1 Meet team, project overview, architecture walkthrough\nWeek Role-based technical onboarding with buddy\n2–4\n7. First-Week Checklist\n# Item Done\n1 Submit original documents to HR\n☐\n2 Receive laptop, ID card and access card\n☐\n3 Log in to email, Teams, PeopleHub and set up MFA\n☐\n4 Complete security and compliance training (score 80%\n☐\nor more)\n5 Sign confidentiality agreement and policy\n☐\nacknowledgements\n6 Enrol in group health insurance and add nominees\n☐\n7 Meet manager and agree 30-60-90 day plan\n☐\n8 Meet buddy and join team stand-up\n☐	db54bc7fa4cc0051f8aa9e40744550cebbd4571a04e8f466445f01580e95fdab	gemini-embedding-2	indexed	2026-10-10 11:03:02.56919
a26b4cdd-99bb-42ef-93f4-b015b14feb56	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-e839e80c	project-001	4	5	5	Page 5	9 Get access to the project repositories and Jira board\n☐\n10 Complete first-week feedback survey\n☐\n8. Probation and Follow-Ups\n• HR check-in on Day 7, Day 30 and Day 90.\n• Probation period is 6 months for L1–L3 and 3 months for L4+,\nsubject to the confirmation process in the Performance Review\nGuidelines.\nExample: Ishita Sharma joins as Engineer (L2) on Project Beacon on\nMonday 6 July 2026. HR verifies her documents by 10:30 AM, IT hands\nover her laptop, and she completes security training on Tuesday. By\nFriday she has merged her first pull request with help from her buddy,\nVikram.	f9e449675d64af9c8c1f5d365170e1ffd10570361a640dad522569d490a9e4d2	gemini-embedding-2	indexed	2026-10-10 11:03:03.1567
cd084b8e-4415-4d0d-988a-f0bfea17917c	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-fc174a6d	project-001	1	2	2	Page 2	Hiring Manager Buddy assignment, 30-60-90 day plan, project\nintroduction\nIT Service Desk Laptop, accounts, access, security briefing\nAdmin & Access card, desk, parking, ID card\nFacilities\nFinance & Salary setup, PF/UAN, bank details\nPayroll\nOnboarding Day-to-day guide for the first 30 days\nBuddy\n3. Pre-Joining (Offer Accepted to Day -1)\nTimeline Action Owner\nOffer Welcome email with joining checklist HR\nacceptance\nT-10 days Background verification (BGV) initiated HR\nthrough third-party agency\nT-7 days Laptop and accessories requested on Manager\nServiceDesk\nT-5 days Buddy assigned; team informed Manager\nT-3 days Email ID and Teams account created IT\n(not yet activated)\nT-1 day Reminder call; confirm reporting time and HR\nlocation\n4. Document Verification\nOriginals must be shown on Day 1; copies are retained.	df84c8a9b6595201384b4269be33d53526d8e7f8be798b6c33b18cb9b79ba24d	gemini-embedding-2	indexed	2026-10-10 11:03:00.260177
368a5242-1e71-4b87-817f-811493efb664	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-fc174a6d	project-001	2	3	3	Page 3	Category Documents\nIdentity Aadhaar, PAN (mandatory), passport (if available)\nAddress Aadhaar or utility bill / rental agreement\nEducation Degree and mark sheets (highest qualification\nmandatory)\nEmployment Relieving letter, last 3 payslips, experience letters from\nprevious employers\nFinancial Cancelled cheque or bank statement, UAN number\nOther 4 passport photographs, medical fitness (for night-shift\nroles)\nIf documents are pending, HR may allow up to 7 working days to\nsubmit, with manager approval. Joining may be withdrawn if BGV finds\nmaterial discrepancies.\n5. Account and Access Creation\nSystem Provided Ready By\nBy\nCompany email and Microsoft IT Day 1, 10:00 AM\nTeams\nPeopleHub (HRMS) HR Day 1\nVPN and multi-factor IT Day 1\nauthentication\nJira, Confluence, GitHub Project Day 2\nEnterprise Admin\nProject-specific environments (for Project Day 3, after\nexample, Atlas staging) Lead security training\nServiceDesk IT Day 1\nAccess follows the least privilege principle. Production access is	632360447a2ef22a637e043d6a3d59225fb3de42a9718e1057c58886434b3881	gemini-embedding-2	indexed	2026-10-10 11:03:01.136599
e923cc2a-37fa-4403-a58b-e8f2448c11f2	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-fc174a6d	project-001	3	4	4	Page 4	granted only after 30 days and manager approval.\n6. Induction and Training\nDay Session\nDay 1 Welcome, company overview, HR policies, benefits\nwalkthrough\nDay 2 Information security and Remote Work Security training\n(mandatory, assessed)\nDay 3 POSH and Code of Conduct awareness (e-learning)\nWeek 1 Meet team, project overview, architecture walkthrough\nWeek Role-based technical onboarding with buddy\n2–4\n7. First-Week Checklist\n# Item Done\n1 Submit original documents to HR\n☐\n2 Receive laptop, ID card and access card\n☐\n3 Log in to email, Teams, PeopleHub and set up MFA\n☐\n4 Complete security and compliance training (score 80%\n☐\nor more)\n5 Sign confidentiality agreement and policy\n☐\nacknowledgements\n6 Enrol in group health insurance and add nominees\n☐\n7 Meet manager and agree 30-60-90 day plan\n☐\n8 Meet buddy and join team stand-up\n☐	db54bc7fa4cc0051f8aa9e40744550cebbd4571a04e8f466445f01580e95fdab	gemini-embedding-2	indexed	2026-10-10 11:03:01.735857
238ce49c-6e0f-46cd-b716-59932da5f71f	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-fc174a6d	project-001	4	5	5	Page 5	9 Get access to the project repositories and Jira board\n☐\n10 Complete first-week feedback survey\n☐\n8. Probation and Follow-Ups\n• HR check-in on Day 7, Day 30 and Day 90.\n• Probation period is 6 months for L1–L3 and 3 months for L4+,\nsubject to the confirmation process in the Performance Review\nGuidelines.\nExample: Ishita Sharma joins as Engineer (L2) on Project Beacon on\nMonday 6 July 2026. HR verifies her documents by 10:30 AM, IT hands\nover her laptop, and she completes security training on Tuesday. By\nFriday she has merged her first pull request with help from her buddy,\nVikram.	f9e449675d64af9c8c1f5d365170e1ffd10570361a640dad522569d490a9e4d2	gemini-embedding-2	indexed	2026-10-10 11:03:02.521869
5cbad8cb-892a-4a70-b306-037d22b0167d	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-5ae9c1e0	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Onboarding Procedure\nDocument NXR-HR-PRC-006\nID\nVersion 2.3\nEffective 1 April 2026\nDate\nOwner HR Operations (Rahul Deshmukh)\nApplies To All new joiners (full-time employees, interns, fixed-\nterm staff)\n1. Purpose\nTo give every new joiner a smooth, compliant and welcoming start, and\nto ensure accounts, equipment, training and documents are ready by\nDay 1.\n2. Roles and Responsibilities\nRole Responsibility\nHR Operations Offer paperwork, document verification, induction\nschedule	869b1f7b99a771fb8d6ed9d37c221e601529bcd2b719d3d3ecb8c135504e39e0	gemini-embedding-2	indexed	2026-10-10 11:02:59.322402
e40aaf05-7a0e-4803-85d2-4167c003f786	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-5ae9c1e0	project-001	1	2	2	Page 2	Hiring Manager Buddy assignment, 30-60-90 day plan, project\nintroduction\nIT Service Desk Laptop, accounts, access, security briefing\nAdmin & Access card, desk, parking, ID card\nFacilities\nFinance & Salary setup, PF/UAN, bank details\nPayroll\nOnboarding Day-to-day guide for the first 30 days\nBuddy\n3. Pre-Joining (Offer Accepted to Day -1)\nTimeline Action Owner\nOffer Welcome email with joining checklist HR\nacceptance\nT-10 days Background verification (BGV) initiated HR\nthrough third-party agency\nT-7 days Laptop and accessories requested on Manager\nServiceDesk\nT-5 days Buddy assigned; team informed Manager\nT-3 days Email ID and Teams account created IT\n(not yet activated)\nT-1 day Reminder call; confirm reporting time and HR\nlocation\n4. Document Verification\nOriginals must be shown on Day 1; copies are retained.	df84c8a9b6595201384b4269be33d53526d8e7f8be798b6c33b18cb9b79ba24d	gemini-embedding-2	indexed	2026-10-10 11:03:00.420462
caf021bc-63d3-435e-92fc-779233bcda1f	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-5ae9c1e0	project-001	2	3	3	Page 3	Category Documents\nIdentity Aadhaar, PAN (mandatory), passport (if available)\nAddress Aadhaar or utility bill / rental agreement\nEducation Degree and mark sheets (highest qualification\nmandatory)\nEmployment Relieving letter, last 3 payslips, experience letters from\nprevious employers\nFinancial Cancelled cheque or bank statement, UAN number\nOther 4 passport photographs, medical fitness (for night-shift\nroles)\nIf documents are pending, HR may allow up to 7 working days to\nsubmit, with manager approval. Joining may be withdrawn if BGV finds\nmaterial discrepancies.\n5. Account and Access Creation\nSystem Provided Ready By\nBy\nCompany email and Microsoft IT Day 1, 10:00 AM\nTeams\nPeopleHub (HRMS) HR Day 1\nVPN and multi-factor IT Day 1\nauthentication\nJira, Confluence, GitHub Project Day 2\nEnterprise Admin\nProject-specific environments (for Project Day 3, after\nexample, Atlas staging) Lead security training\nServiceDesk IT Day 1\nAccess follows the least privilege principle. Production access is	632360447a2ef22a637e043d6a3d59225fb3de42a9718e1057c58886434b3881	gemini-embedding-2	indexed	2026-10-10 11:03:01.721612
37398166-a4cd-424d-a6e4-8489cab4bd33	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-5ae9c1e0	project-001	3	4	4	Page 4	granted only after 30 days and manager approval.\n6. Induction and Training\nDay Session\nDay 1 Welcome, company overview, HR policies, benefits\nwalkthrough\nDay 2 Information security and Remote Work Security training\n(mandatory, assessed)\nDay 3 POSH and Code of Conduct awareness (e-learning)\nWeek 1 Meet team, project overview, architecture walkthrough\nWeek Role-based technical onboarding with buddy\n2–4\n7. First-Week Checklist\n# Item Done\n1 Submit original documents to HR\n☐\n2 Receive laptop, ID card and access card\n☐\n3 Log in to email, Teams, PeopleHub and set up MFA\n☐\n4 Complete security and compliance training (score 80%\n☐\nor more)\n5 Sign confidentiality agreement and policy\n☐\nacknowledgements\n6 Enrol in group health insurance and add nominees\n☐\n7 Meet manager and agree 30-60-90 day plan\n☐\n8 Meet buddy and join team stand-up\n☐	db54bc7fa4cc0051f8aa9e40744550cebbd4571a04e8f466445f01580e95fdab	gemini-embedding-2	indexed	2026-10-10 11:03:02.309625
38e0d784-a1fc-474f-bf95-63c301a6c267	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-5ae9c1e0	project-001	4	5	5	Page 5	9 Get access to the project repositories and Jira board\n☐\n10 Complete first-week feedback survey\n☐\n8. Probation and Follow-Ups\n• HR check-in on Day 7, Day 30 and Day 90.\n• Probation period is 6 months for L1–L3 and 3 months for L4+,\nsubject to the confirmation process in the Performance Review\nGuidelines.\nExample: Ishita Sharma joins as Engineer (L2) on Project Beacon on\nMonday 6 July 2026. HR verifies her documents by 10:30 AM, IT hands\nover her laptop, and she completes security training on Tuesday. By\nFriday she has merged her first pull request with help from her buddy,\nVikram.	f9e449675d64af9c8c1f5d365170e1ffd10570361a640dad522569d490a9e4d2	gemini-embedding-2	indexed	2026-10-10 11:03:03.209362
d86b61ea-7373-4632-bc90-590396d57bd2	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-c2f2c6b2	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Onboarding Procedure\nDocument NXR-HR-PRC-006\nID\nVersion 2.3\nEffective 1 April 2026\nDate\nOwner HR Operations (Rahul Deshmukh)\nApplies To All new joiners (full-time employees, interns, fixed-\nterm staff)\n1. Purpose\nTo give every new joiner a smooth, compliant and welcoming start, and\nto ensure accounts, equipment, training and documents are ready by\nDay 1.\n2. Roles and Responsibilities\nRole Responsibility\nHR Operations Offer paperwork, document verification, induction\nschedule	869b1f7b99a771fb8d6ed9d37c221e601529bcd2b719d3d3ecb8c135504e39e0	gemini-embedding-2	indexed	2026-10-10 11:03:01.124508
0518194a-15a0-42bd-9232-39afef8e5724	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-c2f2c6b2	project-001	1	2	2	Page 2	Hiring Manager Buddy assignment, 30-60-90 day plan, project\nintroduction\nIT Service Desk Laptop, accounts, access, security briefing\nAdmin & Access card, desk, parking, ID card\nFacilities\nFinance & Salary setup, PF/UAN, bank details\nPayroll\nOnboarding Day-to-day guide for the first 30 days\nBuddy\n3. Pre-Joining (Offer Accepted to Day -1)\nTimeline Action Owner\nOffer Welcome email with joining checklist HR\nacceptance\nT-10 days Background verification (BGV) initiated HR\nthrough third-party agency\nT-7 days Laptop and accessories requested on Manager\nServiceDesk\nT-5 days Buddy assigned; team informed Manager\nT-3 days Email ID and Teams account created IT\n(not yet activated)\nT-1 day Reminder call; confirm reporting time and HR\nlocation\n4. Document Verification\nOriginals must be shown on Day 1; copies are retained.	df84c8a9b6595201384b4269be33d53526d8e7f8be798b6c33b18cb9b79ba24d	gemini-embedding-2	indexed	2026-10-10 11:03:01.751726
bc9033b9-549c-400d-9691-ebf265388ca5	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-c2f2c6b2	project-001	2	3	3	Page 3	Category Documents\nIdentity Aadhaar, PAN (mandatory), passport (if available)\nAddress Aadhaar or utility bill / rental agreement\nEducation Degree and mark sheets (highest qualification\nmandatory)\nEmployment Relieving letter, last 3 payslips, experience letters from\nprevious employers\nFinancial Cancelled cheque or bank statement, UAN number\nOther 4 passport photographs, medical fitness (for night-shift\nroles)\nIf documents are pending, HR may allow up to 7 working days to\nsubmit, with manager approval. Joining may be withdrawn if BGV finds\nmaterial discrepancies.\n5. Account and Access Creation\nSystem Provided Ready By\nBy\nCompany email and Microsoft IT Day 1, 10:00 AM\nTeams\nPeopleHub (HRMS) HR Day 1\nVPN and multi-factor IT Day 1\nauthentication\nJira, Confluence, GitHub Project Day 2\nEnterprise Admin\nProject-specific environments (for Project Day 3, after\nexample, Atlas staging) Lead security training\nServiceDesk IT Day 1\nAccess follows the least privilege principle. Production access is	632360447a2ef22a637e043d6a3d59225fb3de42a9718e1057c58886434b3881	gemini-embedding-2	indexed	2026-10-10 11:03:02.389199
763f5e27-ffea-47f2-a91f-a6d5569ec389	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-c2f2c6b2	project-001	3	4	4	Page 4	granted only after 30 days and manager approval.\n6. Induction and Training\nDay Session\nDay 1 Welcome, company overview, HR policies, benefits\nwalkthrough\nDay 2 Information security and Remote Work Security training\n(mandatory, assessed)\nDay 3 POSH and Code of Conduct awareness (e-learning)\nWeek 1 Meet team, project overview, architecture walkthrough\nWeek Role-based technical onboarding with buddy\n2–4\n7. First-Week Checklist\n# Item Done\n1 Submit original documents to HR\n☐\n2 Receive laptop, ID card and access card\n☐\n3 Log in to email, Teams, PeopleHub and set up MFA\n☐\n4 Complete security and compliance training (score 80%\n☐\nor more)\n5 Sign confidentiality agreement and policy\n☐\nacknowledgements\n6 Enrol in group health insurance and add nominees\n☐\n7 Meet manager and agree 30-60-90 day plan\n☐\n8 Meet buddy and join team stand-up\n☐	db54bc7fa4cc0051f8aa9e40744550cebbd4571a04e8f466445f01580e95fdab	gemini-embedding-2	indexed	2026-10-10 11:03:03.031156
b492d191-830f-4d44-b920-787bd9c943ec	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-c2f2c6b2	project-001	4	5	5	Page 5	9 Get access to the project repositories and Jira board\n☐\n10 Complete first-week feedback survey\n☐\n8. Probation and Follow-Ups\n• HR check-in on Day 7, Day 30 and Day 90.\n• Probation period is 6 months for L1–L3 and 3 months for L4+,\nsubject to the confirmation process in the Performance Review\nGuidelines.\nExample: Ishita Sharma joins as Engineer (L2) on Project Beacon on\nMonday 6 July 2026. HR verifies her documents by 10:30 AM, IT hands\nover her laptop, and she completes security training on Tuesday. By\nFriday she has merged her first pull request with help from her buddy,\nVikram.	f9e449675d64af9c8c1f5d365170e1ffd10570361a640dad522569d490a9e4d2	gemini-embedding-2	indexed	2026-10-10 11:03:03.6575
243c5bc9-238c-43e6-88f0-5c2c70d21bd2	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-804c165d	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nEmployee Onboarding Procedure\nDocument NXR-HR-PRC-006\nID\nVersion 2.3\nEffective 1 April 2026\nDate\nOwner HR Operations (Rahul Deshmukh)\nApplies To All new joiners (full-time employees, interns, fixed-\nterm staff)\n1. Purpose\nTo give every new joiner a smooth, compliant and welcoming start, and\nto ensure accounts, equipment, training and documents are ready by\nDay 1.\n2. Roles and Responsibilities\nRole Responsibility\nHR Operations Offer paperwork, document verification, induction\nschedule	869b1f7b99a771fb8d6ed9d37c221e601529bcd2b719d3d3ecb8c135504e39e0	gemini-embedding-2	indexed	2026-10-10 11:03:01.713367
c3051b51-a592-4992-82bd-6f06e436cc9b	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-804c165d	project-001	1	2	2	Page 2	Hiring Manager Buddy assignment, 30-60-90 day plan, project\nintroduction\nIT Service Desk Laptop, accounts, access, security briefing\nAdmin & Access card, desk, parking, ID card\nFacilities\nFinance & Salary setup, PF/UAN, bank details\nPayroll\nOnboarding Day-to-day guide for the first 30 days\nBuddy\n3. Pre-Joining (Offer Accepted to Day -1)\nTimeline Action Owner\nOffer Welcome email with joining checklist HR\nacceptance\nT-10 days Background verification (BGV) initiated HR\nthrough third-party agency\nT-7 days Laptop and accessories requested on Manager\nServiceDesk\nT-5 days Buddy assigned; team informed Manager\nT-3 days Email ID and Teams account created IT\n(not yet activated)\nT-1 day Reminder call; confirm reporting time and HR\nlocation\n4. Document Verification\nOriginals must be shown on Day 1; copies are retained.	df84c8a9b6595201384b4269be33d53526d8e7f8be798b6c33b18cb9b79ba24d	gemini-embedding-2	indexed	2026-10-10 11:03:02.302242
d3a16b69-7b92-41c0-a08d-ca0eb8de0935	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-804c165d	project-001	2	3	3	Page 3	Category Documents\nIdentity Aadhaar, PAN (mandatory), passport (if available)\nAddress Aadhaar or utility bill / rental agreement\nEducation Degree and mark sheets (highest qualification\nmandatory)\nEmployment Relieving letter, last 3 payslips, experience letters from\nprevious employers\nFinancial Cancelled cheque or bank statement, UAN number\nOther 4 passport photographs, medical fitness (for night-shift\nroles)\nIf documents are pending, HR may allow up to 7 working days to\nsubmit, with manager approval. Joining may be withdrawn if BGV finds\nmaterial discrepancies.\n5. Account and Access Creation\nSystem Provided Ready By\nBy\nCompany email and Microsoft IT Day 1, 10:00 AM\nTeams\nPeopleHub (HRMS) HR Day 1\nVPN and multi-factor IT Day 1\nauthentication\nJira, Confluence, GitHub Project Day 2\nEnterprise Admin\nProject-specific environments (for Project Day 3, after\nexample, Atlas staging) Lead security training\nServiceDesk IT Day 1\nAccess follows the least privilege principle. Production access is	632360447a2ef22a637e043d6a3d59225fb3de42a9718e1057c58886434b3881	gemini-embedding-2	indexed	2026-10-10 11:03:02.930543
e7dd88d8-a5c4-4865-8422-cf044921d31a	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-804c165d	project-001	3	4	4	Page 4	granted only after 30 days and manager approval.\n6. Induction and Training\nDay Session\nDay 1 Welcome, company overview, HR policies, benefits\nwalkthrough\nDay 2 Information security and Remote Work Security training\n(mandatory, assessed)\nDay 3 POSH and Code of Conduct awareness (e-learning)\nWeek 1 Meet team, project overview, architecture walkthrough\nWeek Role-based technical onboarding with buddy\n2–4\n7. First-Week Checklist\n# Item Done\n1 Submit original documents to HR\n☐\n2 Receive laptop, ID card and access card\n☐\n3 Log in to email, Teams, PeopleHub and set up MFA\n☐\n4 Complete security and compliance training (score 80%\n☐\nor more)\n5 Sign confidentiality agreement and policy\n☐\nacknowledgements\n6 Enrol in group health insurance and add nominees\n☐\n7 Meet manager and agree 30-60-90 day plan\n☐\n8 Meet buddy and join team stand-up\n☐	db54bc7fa4cc0051f8aa9e40744550cebbd4571a04e8f466445f01580e95fdab	gemini-embedding-2	indexed	2026-10-10 11:03:03.595286
2959fd55-8101-4e1d-9f9d-349c9d2e37cd	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-98940217eca3	ver-804c165d	project-001	4	5	5	Page 5	9 Get access to the project repositories and Jira board\n☐\n10 Complete first-week feedback survey\n☐\n8. Probation and Follow-Ups\n• HR check-in on Day 7, Day 30 and Day 90.\n• Probation period is 6 months for L1–L3 and 3 months for L4+,\nsubject to the confirmation process in the Performance Review\nGuidelines.\nExample: Ishita Sharma joins as Engineer (L2) on Project Beacon on\nMonday 6 July 2026. HR verifies her documents by 10:30 AM, IT hands\nover her laptop, and she completes security training on Tuesday. By\nFriday she has merged her first pull request with help from her buddy,\nVikram.	f9e449675d64af9c8c1f5d365170e1ffd10570361a640dad522569d490a9e4d2	gemini-embedding-2	indexed	2026-10-10 11:03:04.182287
8bc6bca9-ee57-4b38-ab2b-f1bbe2730a34	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-b51a7e3c	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nTraining and Development Policy\nDocument NXR-HR-POL-011\nID\nVersion 2.2\nEffective 1 April 2026\nDate\nOwner Learning & Development (Tanvi Kapoor)\nApplies To All confirmed employees; mandatory training applies\nto everyone\n1. Purpose\nTo build the skills Nexora needs for its projects and to support each\nemployee's growth through structured learning, certifications and\nmentoring.\n2. Types of Training\nType Description Examples	4a911392e0bab1d3529386342dc647351ad9dd84f0d6b6a601ad21d89fe0610b	gemini-embedding-2	indexed	2026-10-10 11:03:24.705438
22dd1834-36b2-45cd-b517-39d3ad655c87	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-b51a7e3c	project-001	1	2	2	Page 2	Mandatory Required for all Information security, POSH,\nemployees Code of Conduct, data\nprivacy\nRole- Linked to job role and Cloud architecture for Atlas,\nbased project needs secure coding, testing\nautomation\nLeadership For L4 and above and People management,\nhigh-potential stakeholder communication\nemployees\nSelf-driven Chosen by employee Online courses, conferences\nand approved by\nmanager\n3. Eligibility\nGroup Eligibility\nProbationers Mandatory and onboarding training\nonly\nConfirmed employees (6+ Learning budget, certifications,\nmonths) conferences\nEmployees with rating 2 or 1 Only training in the improvement\nplan\nInterns Internal bootcamp only\n4. Annual Learning Budget (per employee,\nper financial year)\nLevel Budget Notes\nL1–L3 ₹25,000 Courses, books, certifications	14ae717fe1db5edd241ca16ef044537b2ece5221d726ef3462b361ba1d402989	gemini-embedding-2	indexed	2026-10-10 11:03:25.471127
413947a3-caad-4661-af7d-77aecd89c7b2	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-e9e9af6c	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nTraining and Development Policy\nDocument NXR-HR-POL-011\nID\nVersion 2.2\nEffective 1 April 2026\nDate\nOwner Learning & Development (Tanvi Kapoor)\nApplies To All confirmed employees; mandatory training applies\nto everyone\n1. Purpose\nTo build the skills Nexora needs for its projects and to support each\nemployee's growth through structured learning, certifications and\nmentoring.\n2. Types of Training\nType Description Examples	4a911392e0bab1d3529386342dc647351ad9dd84f0d6b6a601ad21d89fe0610b	gemini-embedding-2	indexed	2026-10-10 11:03:25.102511
04cc04e5-d768-41fa-bcb1-9f95d60dfb13	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-b51a7e3c	project-001	2	3	3	Page 3	L4–L5 ₹40,000 Includes one conference per\nyear\nL6 and above ₹60,000 Includes leadership programmes\nUnused budget does not carry forward. Teams may pool budget for\ngroup workshops with L&D approval. Each employee also gets 5 paid\nlearning days per year for courses, exams or conferences.\n5. Approved Courses and Certifications\nApproved providers: Coursera for Business, Udemy Business,\nPluralsight, the internal Nexora Academy, and certification bodies listed\nbelow.\nTrack Approved Certifications (examples)\nCloud AWS Solutions Architect, Azure Administrator,\nGoogle Cloud Professional\nSecurity CISSP, CEH, CompTIA Security+\nData and AI Databricks Data Engineer, Azure Data Scientist,\nTensorFlow Developer\nQuality ISTQB Advanced, Selenium certification\nAgile and PMP, CSM, SAFe Practitioner\nManagement\nCourses not on the list can be approved if they clearly support the role\nand project (L&D decision within 3 working days).\n6. Certification Support\n• Exam fee: Fully reimbursed on first attempt after passing, within\nthe learning budget. Retake fees are borne by the employee.\n• Exam leave: 1 paid learning day per exam plus 2 study days for	3ceaac1cf0f067861473abd037889cb57534e0930ebaca79f42ce205e2fed347	gemini-embedding-2	indexed	2026-10-10 11:03:26.069131
492db15e-de85-4b31-8c2f-b22154b477ec	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-b51a7e3c	project-001	3	4	4	Page 4	exams above ₹30,000 in fee.\n• Certification bonus: ₹5,000 for associate-level and ₹10,000 for\nprofessional/expert-level certifications aligned to business needs.\n• Service agreement: Training sponsored above ₹50,000 requires\na 12-month service commitment. If the employee leaves earlier,\nthe cost is recovered pro-rata from F&F.\n7. How to Apply\n1. Select the course on PeopleHub → Learning → Request\nTraining.\n2. Manager approves (for alignment with project needs) within 3\nworking days.\n3. L&D validates budget and issues the payment or reimbursement\nvoucher.\n4. Employee completes the course, uploads the certificate within 15\ndays, and shares learning in a team session.\n8. Evaluation of Training\n• Level 1 – Reaction: Feedback survey after each programme\n(target 4.2/5 or above).\n• Level 2 – Learning: Assessment or certification score.\n• Level 3 – Application: Manager review at 60 days on whether\nskills are used on the project.\n• Level 4 – Impact: L&D reports annually on productivity, quality\nand retention outcomes.\nL&D reviews training effectiveness in the Annual HR Report.\n9. Mentoring and Internal Programmes\nNexora Academy runs a 12-week Cloud Engineering Bootcamp,	db46bed65b27fbc741edd7f9fc3ebda9a387c93f191f4e74f89768e872760007	gemini-embedding-2	indexed	2026-10-10 11:03:26.8613
d8b73cd8-9a93-4271-9d88-c17fa64ac83a	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-b51a7e3c	project-001	4	5	5	Page 5	quarterly tech talks, and a mentoring programme pairing each L1–L3\nemployee with a senior mentor for 6 months.\nExample: Aditi (Senior Engineer, L3) enrols in the AWS Solutions\nArchitect – Professional exam costing ₹26,000. Her manager approves it\nfor the Atlas migration. She takes 3 learning days, passes on her first\nattempt, claims the fee within her ₹25,000 budget plus ₹1,000 from the\nmanager's team pool, and receives a ₹10,000 certification bonus. No\nservice commitment applies because the cost is under ₹50,000.	67fb19add87dd2cc8684c4b1e5dcdf527adc63a60e8e16dea5b0240b40b4e90c	gemini-embedding-2	indexed	2026-10-10 11:03:27.424045
04f9d665-1f5b-4468-a80f-00d484fb916c	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-0621e8a5	project-001	0	1	1	Page 1	Nexora Technologies Pvt. Ltd.\nTraining and Development Policy\nDocument NXR-HR-POL-011\nID\nVersion 2.2\nEffective 1 April 2026\nDate\nOwner Learning & Development (Tanvi Kapoor)\nApplies To All confirmed employees; mandatory training applies\nto everyone\n1. Purpose\nTo build the skills Nexora needs for its projects and to support each\nemployee's growth through structured learning, certifications and\nmentoring.\n2. Types of Training\nType Description Examples	4a911392e0bab1d3529386342dc647351ad9dd84f0d6b6a601ad21d89fe0610b	gemini-embedding-2	indexed	2026-10-10 11:03:25.447578
b5ad9fd9-6122-47f5-b51e-f86460fc1425	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-0621e8a5	project-001	1	2	2	Page 2	Mandatory Required for all Information security, POSH,\nemployees Code of Conduct, data\nprivacy\nRole- Linked to job role and Cloud architecture for Atlas,\nbased project needs secure coding, testing\nautomation\nLeadership For L4 and above and People management,\nhigh-potential stakeholder communication\nemployees\nSelf-driven Chosen by employee Online courses, conferences\nand approved by\nmanager\n3. Eligibility\nGroup Eligibility\nProbationers Mandatory and onboarding training\nonly\nConfirmed employees (6+ Learning budget, certifications,\nmonths) conferences\nEmployees with rating 2 or 1 Only training in the improvement\nplan\nInterns Internal bootcamp only\n4. Annual Learning Budget (per employee,\nper financial year)\nLevel Budget Notes\nL1–L3 ₹25,000 Courses, books, certifications	14ae717fe1db5edd241ca16ef044537b2ece5221d726ef3462b361ba1d402989	gemini-embedding-2	indexed	2026-10-10 11:03:26.047633
7cead88b-360b-4aee-a081-4218ca6f1f0c	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-0621e8a5	project-001	2	3	3	Page 3	L4–L5 ₹40,000 Includes one conference per\nyear\nL6 and above ₹60,000 Includes leadership programmes\nUnused budget does not carry forward. Teams may pool budget for\ngroup workshops with L&D approval. Each employee also gets 5 paid\nlearning days per year for courses, exams or conferences.\n5. Approved Courses and Certifications\nApproved providers: Coursera for Business, Udemy Business,\nPluralsight, the internal Nexora Academy, and certification bodies listed\nbelow.\nTrack Approved Certifications (examples)\nCloud AWS Solutions Architect, Azure Administrator,\nGoogle Cloud Professional\nSecurity CISSP, CEH, CompTIA Security+\nData and AI Databricks Data Engineer, Azure Data Scientist,\nTensorFlow Developer\nQuality ISTQB Advanced, Selenium certification\nAgile and PMP, CSM, SAFe Practitioner\nManagement\nCourses not on the list can be approved if they clearly support the role\nand project (L&D decision within 3 working days).\n6. Certification Support\n• Exam fee: Fully reimbursed on first attempt after passing, within\nthe learning budget. Retake fees are borne by the employee.\n• Exam leave: 1 paid learning day per exam plus 2 study days for	3ceaac1cf0f067861473abd037889cb57534e0930ebaca79f42ce205e2fed347	gemini-embedding-2	indexed	2026-10-10 11:03:26.627922
d91321e4-23fb-4664-94c3-4f6ec4c71cab	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-e9e9af6c	project-001	1	2	2	Page 2	Mandatory Required for all Information security, POSH,\nemployees Code of Conduct, data\nprivacy\nRole- Linked to job role and Cloud architecture for Atlas,\nbased project needs secure coding, testing\nautomation\nLeadership For L4 and above and People management,\nhigh-potential stakeholder communication\nemployees\nSelf-driven Chosen by employee Online courses, conferences\nand approved by\nmanager\n3. Eligibility\nGroup Eligibility\nProbationers Mandatory and onboarding training\nonly\nConfirmed employees (6+ Learning budget, certifications,\nmonths) conferences\nEmployees with rating 2 or 1 Only training in the improvement\nplan\nInterns Internal bootcamp only\n4. Annual Learning Budget (per employee,\nper financial year)\nLevel Budget Notes\nL1–L3 ₹25,000 Courses, books, certifications	14ae717fe1db5edd241ca16ef044537b2ece5221d726ef3462b361ba1d402989	gemini-embedding-2	indexed	2026-10-10 11:03:25.781169
88a76aa5-d00a-4d3a-99a7-fcd1bc85e358	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-0621e8a5	project-001	3	4	4	Page 4	exams above ₹30,000 in fee.\n• Certification bonus: ₹5,000 for associate-level and ₹10,000 for\nprofessional/expert-level certifications aligned to business needs.\n• Service agreement: Training sponsored above ₹50,000 requires\na 12-month service commitment. If the employee leaves earlier,\nthe cost is recovered pro-rata from F&F.\n7. How to Apply\n1. Select the course on PeopleHub → Learning → Request\nTraining.\n2. Manager approves (for alignment with project needs) within 3\nworking days.\n3. L&D validates budget and issues the payment or reimbursement\nvoucher.\n4. Employee completes the course, uploads the certificate within 15\ndays, and shares learning in a team session.\n8. Evaluation of Training\n• Level 1 – Reaction: Feedback survey after each programme\n(target 4.2/5 or above).\n• Level 2 – Learning: Assessment or certification score.\n• Level 3 – Application: Manager review at 60 days on whether\nskills are used on the project.\n• Level 4 – Impact: L&D reports annually on productivity, quality\nand retention outcomes.\nL&D reviews training effectiveness in the Annual HR Report.\n9. Mentoring and Internal Programmes\nNexora Academy runs a 12-week Cloud Engineering Bootcamp,	db46bed65b27fbc741edd7f9fc3ebda9a387c93f191f4e74f89768e872760007	gemini-embedding-2	indexed	2026-10-10 11:03:27.240259
383da707-2113-424b-8a15-3b47077bfc0a	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-0621e8a5	project-001	4	5	5	Page 5	quarterly tech talks, and a mentoring programme pairing each L1–L3\nemployee with a senior mentor for 6 months.\nExample: Aditi (Senior Engineer, L3) enrols in the AWS Solutions\nArchitect – Professional exam costing ₹26,000. Her manager approves it\nfor the Atlas migration. She takes 3 learning days, passes on her first\nattempt, claims the fee within her ₹25,000 budget plus ₹1,000 from the\nmanager's team pool, and receives a ₹10,000 certification bonus. No\nservice commitment applies because the cost is under ₹50,000.	67fb19add87dd2cc8684c4b1e5dcdf527adc63a60e8e16dea5b0240b40b4e90c	gemini-embedding-2	indexed	2026-10-10 11:03:27.835703
eeccd468-c916-48d1-9b5b-0d353dc565af	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-e9e9af6c	project-001	2	3	3	Page 3	L4–L5 ₹40,000 Includes one conference per\nyear\nL6 and above ₹60,000 Includes leadership programmes\nUnused budget does not carry forward. Teams may pool budget for\ngroup workshops with L&D approval. Each employee also gets 5 paid\nlearning days per year for courses, exams or conferences.\n5. Approved Courses and Certifications\nApproved providers: Coursera for Business, Udemy Business,\nPluralsight, the internal Nexora Academy, and certification bodies listed\nbelow.\nTrack Approved Certifications (examples)\nCloud AWS Solutions Architect, Azure Administrator,\nGoogle Cloud Professional\nSecurity CISSP, CEH, CompTIA Security+\nData and AI Databricks Data Engineer, Azure Data Scientist,\nTensorFlow Developer\nQuality ISTQB Advanced, Selenium certification\nAgile and PMP, CSM, SAFe Practitioner\nManagement\nCourses not on the list can be approved if they clearly support the role\nand project (L&D decision within 3 working days).\n6. Certification Support\n• Exam fee: Fully reimbursed on first attempt after passing, within\nthe learning budget. Retake fees are borne by the employee.\n• Exam leave: 1 paid learning day per exam plus 2 study days for	3ceaac1cf0f067861473abd037889cb57534e0930ebaca79f42ce205e2fed347	gemini-embedding-2	indexed	2026-10-10 11:03:26.658833
afd7d43b-3730-4b0c-8abd-25e0dec8fe13	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-e9e9af6c	project-001	3	4	4	Page 4	exams above ₹30,000 in fee.\n• Certification bonus: ₹5,000 for associate-level and ₹10,000 for\nprofessional/expert-level certifications aligned to business needs.\n• Service agreement: Training sponsored above ₹50,000 requires\na 12-month service commitment. If the employee leaves earlier,\nthe cost is recovered pro-rata from F&F.\n7. How to Apply\n1. Select the course on PeopleHub → Learning → Request\nTraining.\n2. Manager approves (for alignment with project needs) within 3\nworking days.\n3. L&D validates budget and issues the payment or reimbursement\nvoucher.\n4. Employee completes the course, uploads the certificate within 15\ndays, and shares learning in a team session.\n8. Evaluation of Training\n• Level 1 – Reaction: Feedback survey after each programme\n(target 4.2/5 or above).\n• Level 2 – Learning: Assessment or certification score.\n• Level 3 – Application: Manager review at 60 days on whether\nskills are used on the project.\n• Level 4 – Impact: L&D reports annually on productivity, quality\nand retention outcomes.\nL&D reviews training effectiveness in the Annual HR Report.\n9. Mentoring and Internal Programmes\nNexora Academy runs a 12-week Cloud Engineering Bootcamp,	db46bed65b27fbc741edd7f9fc3ebda9a387c93f191f4e74f89768e872760007	gemini-embedding-2	indexed	2026-10-10 11:03:27.244802
308c6702-9577-4fff-b6bd-082ffc2d3d16	df672f52-b432-45f1-b1a6-4b4b78e23065	doc-4f328576121e	ver-e9e9af6c	project-001	4	5	5	Page 5	quarterly tech talks, and a mentoring programme pairing each L1–L3\nemployee with a senior mentor for 6 months.\nExample: Aditi (Senior Engineer, L3) enrols in the AWS Solutions\nArchitect – Professional exam costing ₹26,000. Her manager approves it\nfor the Atlas migration. She takes 3 learning days, passes on her first\nattempt, claims the fee within her ₹25,000 budget plus ₹1,000 from the\nmanager's team pool, and receives a ₹10,000 certification bonus. No\nservice commitment applies because the cost is under ₹50,000.	67fb19add87dd2cc8684c4b1e5dcdf527adc63a60e8e16dea5b0240b40b4e90c	gemini-embedding-2	indexed	2026-10-10 11:03:27.812681
\.


--
-- Data for Name: classification_levels; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.classification_levels (tenant_id, level, name) FROM stdin;
\.


--
-- Data for Name: company_roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.company_roles (id, name, key, rank_level, description, permissions_json, created_at) FROM stdin;
6	Executive Admin	admin	1	Root System Administrator & C-Suite Executive	["chat", "documents:view"]	2026-10-07 18:23:20.322704
7	Department Head	hr	2	Department & HR Manager Access	["chat", "documents:view"]	2026-10-07 18:23:20.322704
9	Team Manager	manager	3	Team Lead & Project Manager Access	["chat", "documents:view"]	2026-10-07 18:23:20.322704
10	Staff Employee	employee	4	General Staff & Individual Contributor Access	["chat", "documents:view"]	2026-10-07 18:23:20.322704
11	Team Lead	team_lead	3	Project Leads & Senior Engineers	["chat", "documents:view"]	2026-10-07 19:00:14.210703
12	Lead AI Architect	lead_ai_architect	3	Oversees RAG pipeline and vector search algorithms	["chat", "documents:view", "documents:manage", "analytics:view"]	2026-10-09 10:54:44.678689
8	Finance	finance	2	Finance departmental role (Rank Level 2)	["chat", "documents:view"]	2026-10-07 18:23:20.322704
13	Social media	social_media	6	Social media departmental role (Rank Level 6)	["chat", "documents:view"]	2026-10-10 14:59:41.507599
\.


--
-- Data for Name: conversations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.conversations (id, tenant_id, user_id, project_id, title, created_at, updated_at, deleted_at) FROM stdin;
b451ca90-b22a-44b0-b2ae-4944a8494f54	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	What is the annual leave and PTO rollover policy?	2026-10-06 16:28:56.488705+05:30	2026-10-06 16:28:56.488705+05:30	\N
676c64ca-bc65-4b8e-80c8-ea968701569d	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	What are the executive salary bands and bonus multipliers?	2026-10-06 16:28:56.649457+05:30	2026-10-06 16:28:56.649457+05:30	\N
8c82c91e-8c91-43f2-ba67-0310bff1c782	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	891113ac-2816-4143-ac67-f2e8684d39da	\N	What are the executive salary bands and bonus multipliers?	2026-10-06 16:28:56.779325+05:30	2026-10-06 16:28:56.779325+05:30	\N
0bff4c31-6c3d-47b1-8870-2c2a8745c492	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	891113ac-2816-4143-ac67-f2e8684d39da	\N	Write Java code for binary search algorithm.	2026-10-06 16:28:56.884747+05:30	2026-10-06 16:28:56.885747+05:30	\N
f5679689-b442-4c11-8fbd-1f86e531a201	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	Where are fire emergency assembly points?	2026-10-06 16:28:56.980268+05:30	2026-10-06 16:28:56.980268+05:30	\N
6ce957c3-414e-45f8-8131-68fd02755d9a	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	What is the annual leave and PTO rollover policy?	2026-10-06 16:30:14.880581+05:30	2026-10-06 16:30:14.880581+05:30	\N
1c4a0119-c33e-4e1f-bd27-0377827f2357	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	What are the executive salary bands and bonus multipliers?	2026-10-06 16:30:15.024332+05:30	2026-10-06 16:30:15.024332+05:30	\N
671f00d0-fc8a-49e7-ae63-2e265fd34521	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	891113ac-2816-4143-ac67-f2e8684d39da	\N	What are the executive salary bands and bonus multipliers?	2026-10-06 16:30:15.147192+05:30	2026-10-06 16:30:15.147192+05:30	\N
c3bb329b-8cf3-47ba-a9b5-33317446aa00	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	891113ac-2816-4143-ac67-f2e8684d39da	\N	Write Java code for binary search algorithm.	2026-10-06 16:30:15.25534+05:30	2026-10-06 16:30:15.25534+05:30	\N
f9821b76-8662-4886-b18a-e0ce590fa0b6	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	Where are fire emergency assembly points?	2026-10-06 16:30:15.348031+05:30	2026-10-06 16:30:15.348031+05:30	\N
45b96c4d-eaa6-42b1-bee0-2cc96087f9b1	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	What is the annual leave and PTO rollover policy?	2026-10-06 16:31:20.987072+05:30	2026-10-06 16:31:20.987072+05:30	\N
39d63abe-0acb-4745-ae96-bf3c02ca0e05	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	What are the executive salary bands and bonus multipliers?	2026-10-06 16:31:21.126143+05:30	2026-10-06 16:31:21.126143+05:30	\N
3197608e-547f-4645-8148-57b832df6936	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	891113ac-2816-4143-ac67-f2e8684d39da	\N	What are the executive salary bands and bonus multipliers?	2026-10-06 16:31:21.261855+05:30	2026-10-06 16:31:21.261855+05:30	\N
0b2ff35e-c149-46a3-ad34-e3a398018faa	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	891113ac-2816-4143-ac67-f2e8684d39da	\N	Write Java code for binary search algorithm.	2026-10-06 16:31:21.366188+05:30	2026-10-06 16:31:21.366188+05:30	\N
f9352fcf-70b3-47ff-a30f-90a7628e2ae8	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	Where are fire emergency assembly points?	2026-10-06 16:31:21.45995+05:30	2026-10-06 16:31:21.45995+05:30	\N
d78197d1-2f1d-42df-8d4a-21e49472cab0	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	What is the annual leave and PTO rollover policy?	2026-10-06 22:02:02.650097+05:30	2026-10-06 22:02:02.650097+05:30	\N
5bcb3c80-ce35-4c0d-af12-a5ee2e8f8732	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	What are the executive salary bands and bonus multipliers?	2026-10-06 22:02:02.79266+05:30	2026-10-06 22:02:02.79266+05:30	\N
0630674b-98bc-4154-9da8-eced48fad12f	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	891113ac-2816-4143-ac67-f2e8684d39da	\N	What are the executive salary bands and bonus multipliers?	2026-10-06 22:02:02.926898+05:30	2026-10-06 22:02:02.926898+05:30	\N
ed69c5e5-33cf-4637-82b8-6266266fe490	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	891113ac-2816-4143-ac67-f2e8684d39da	\N	Write Java code for binary search algorithm.	2026-10-06 22:02:03.067642+05:30	2026-10-06 22:02:03.067642+05:30	\N
14bac758-65fd-45fe-b904-ce7ad0336235	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	Where are fire emergency assembly points?	2026-10-06 22:02:03.20197+05:30	2026-10-06 22:02:03.20197+05:30	\N
4bd9ad22-4314-42b3-8cf9-cf4b860b2b1f	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	What is our annual leave and PTO rollover policy?	2026-10-06 22:12:16.824392+05:30	2026-10-06 22:12:16.824392+05:30	\N
\.


--
-- Data for Name: document_acl_entries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.document_acl_entries (id, tenant_id, document_id, principal_type, principal_id, external_ref, effect, permission, origin, created_by, created_at, principal_key) FROM stdin;
a09d10ec-0614-4159-ab4b-9bf9a6d21a2b	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	821709cd-804b-4fa8-8248-aea199f33c25	role	0526fb72-dad7-4d22-a3a3-287b3391cc5b	\N	allow	read	manual	\N	2026-10-07 11:34:28.883851+05:30	\N
d0d4fae1-dbad-4735-ae9f-50678dae5504	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	821709cd-804b-4fa8-8248-aea199f33c25	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:28.883851+05:30	\N
ce23f582-251a-48fc-a8f7-35d0098330f2	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0cae3952-0367-42d3-ae95-6292b040bd78	role	0526fb72-dad7-4d22-a3a3-287b3391cc5b	\N	allow	read	manual	\N	2026-10-07 11:34:33.821513+05:30	\N
1188c30e-8010-4f16-8924-e46c07cbaaf5	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0cae3952-0367-42d3-ae95-6292b040bd78	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:33.821513+05:30	\N
47b4e789-aecb-4974-8d76-97abff83a92c	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	99c59e4e-859e-4fbb-b73d-ef74255c7959	role	0526fb72-dad7-4d22-a3a3-287b3391cc5b	\N	allow	read	manual	\N	2026-10-07 11:34:34.272371+05:30	\N
991521fb-41a6-4d2a-b802-84b47486dd50	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	99c59e4e-859e-4fbb-b73d-ef74255c7959	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:34.272371+05:30	\N
4f7a0125-47f3-4299-9f69-93754bb9e3e2	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	6a0bdfef-e2e0-4ae6-9ff6-f961b823aae7	role	0526fb72-dad7-4d22-a3a3-287b3391cc5b	\N	allow	read	manual	\N	2026-10-07 11:34:34.865246+05:30	\N
d5d73f4d-7f6f-4eef-b093-60fbba79d5dd	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	6a0bdfef-e2e0-4ae6-9ff6-f961b823aae7	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:34.865246+05:30	\N
e70394ec-e961-4860-a5f6-7b94565fb55a	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f9e16941-656d-448f-b9ac-afc7266e08fa	role	0526fb72-dad7-4d22-a3a3-287b3391cc5b	\N	allow	read	manual	\N	2026-10-07 11:34:35.827699+05:30	\N
e7dc63c4-3cb9-402a-8f78-03075133d39c	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f9e16941-656d-448f-b9ac-afc7266e08fa	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:35.827699+05:30	\N
c185c25d-1fde-4cab-86c3-79178699854b	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0c9306b3-b762-4445-a63d-860d2c264ae7	role	0526fb72-dad7-4d22-a3a3-287b3391cc5b	\N	allow	read	manual	\N	2026-10-07 11:34:36.277459+05:30	\N
294fb329-2491-4b47-ac0c-a2c08934ca69	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0c9306b3-b762-4445-a63d-860d2c264ae7	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:36.277459+05:30	\N
7b76c381-9673-44cb-9609-edf5fa68388a	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bf65933a-d596-4ee3-8eec-e02439471f21	role	0526fb72-dad7-4d22-a3a3-287b3391cc5b	\N	allow	read	manual	\N	2026-10-07 11:34:36.990999+05:30	\N
1283e2c8-908d-4a6b-9191-d7067e580f6a	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bf65933a-d596-4ee3-8eec-e02439471f21	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:36.990999+05:30	\N
7b6eb612-b3d5-47b2-ba11-988930f2e9ef	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	7baec03d-595f-46b9-b318-812bfb26a367	role	0526fb72-dad7-4d22-a3a3-287b3391cc5b	\N	allow	read	manual	\N	2026-10-07 11:34:37.663184+05:30	\N
1f3548c7-dccd-43db-9a24-88e9aa457647	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	7baec03d-595f-46b9-b318-812bfb26a367	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:37.663184+05:30	\N
11d8a72d-4fa6-4c65-ad16-b2058a785fca	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	6ea34021-5d19-48e2-ba00-06c5940748ac	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:37.956374+05:30	\N
c9fb7f4a-4d72-4ba1-b6ad-00633c653fee	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	8a38d06e-a555-4a26-afcd-5497187371bd	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:38.777414+05:30	\N
00476278-f614-4032-85eb-3958ea04c7e8	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bc95f7c6-8a8c-42eb-99d1-4384380c80d4	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:39.407995+05:30	\N
55939e47-179f-463e-8a80-930a5578f3a2	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	ce7bc5dd-4346-490f-a26f-24b6451e2528	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:40.782881+05:30	\N
f09d7b5d-5093-4e00-aedd-7363b0d786b6	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	8403a264-5148-47cd-9103-696d0038f21b	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:41.760075+05:30	\N
87fb8bfd-623f-48d3-9656-dc95d7dcdcfd	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	53e5e91e-06e4-4dc3-8880-d86bbb4e7d02	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:42.574159+05:30	\N
0b22d38b-8ead-49a9-8405-48266441cbf8	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	8a3666c1-3769-48a8-b241-31519dca1e8b	role	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	allow	read	manual	\N	2026-10-07 11:34:43.553363+05:30	\N
bb40d46f-24b5-4a80-9653-c1855384877a	\N	doc-f4de4672f657	\N	\N	\N	allow	read	manual	\N	2026-10-07 15:27:01.12028+05:30	r:admin
82028205-11d2-4277-a13b-87420fbc51d5	\N	doc-f4de4672f657	\N	\N	\N	allow	read	manual	\N	2026-10-07 15:27:01.120623+05:30	t:tenant-001
63ed4c40-327f-4f09-acec-1ebe41d588cc	\N	doc-f4de4672f657	\N	\N	\N	allow	read	manual	\N	2026-10-07 15:27:01.120623+05:30	r:hr
27cd1948-da46-422d-a327-827db8971f14	\N	doc-98940217eca3	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.156728+05:30	r:finance
db601eaf-736b-4aae-b4d7-463b4d9b06b9	\N	doc-98940217eca3	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.156728+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
31d4ea70-7151-46e5-8edd-acb0f55e3803	\N	doc-98940217eca3	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.156728+05:30	r:hr
07e85e34-4bca-49fa-b60f-1980c8f9443a	\N	doc-98940217eca3	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.156728+05:30	r:manager
16792b35-2c4c-4b6a-965f-3d256064d6f4	\N	doc-98940217eca3	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.156728+05:30	r:admin
95536bc7-53f1-4fa7-bb0c-af885c99c12c	\N	doc-98940217eca3	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.156728+05:30	r:employee
173198b5-dbdb-4977-b785-c4e3f1fb933d	\N	doc-15c4f8adcd3f	\N	\N	\N	allow	read	source_sync	\N	2026-10-09 04:23:11.863146+05:30	t:a3424830-6d45-4ad8-a43b-a5fdf70d691d
8f914070-93ad-4a5b-8edd-c594413d858c	\N	doc-15c4f8adcd3f	\N	\N	\N	allow	read	source_sync	\N	2026-10-09 04:23:11.863146+05:30	r:manager
9329525a-cdc8-4a2e-bbe6-9607b0a5ec54	\N	doc-15c4f8adcd3f	\N	\N	\N	allow	read	source_sync	\N	2026-10-09 04:23:11.863146+05:30	r:hr
cfb40ca3-ab79-4dba-b8f1-a56f56eedf57	\N	doc-15c4f8adcd3f	\N	\N	\N	allow	read	source_sync	\N	2026-10-09 04:23:11.863146+05:30	r:finance
0597d861-9f15-406f-8075-a41bc97e3acd	\N	doc-15c4f8adcd3f	\N	\N	\N	allow	read	source_sync	\N	2026-10-09 04:23:11.863146+05:30	p:project-001
9e5bf40e-d675-4deb-8502-af5981b160f7	\N	doc-15c4f8adcd3f	\N	\N	\N	allow	read	source_sync	\N	2026-10-09 04:23:11.863146+05:30	r:admin
09332ab4-782d-4571-8caa-08342742a988	\N	doc-15c4f8adcd3f	\N	\N	\N	allow	read	source_sync	\N	2026-10-09 04:23:11.863146+05:30	g:group-hr
19b85ffb-4603-426c-8960-0b5d2cfd589a	\N	doc-15c4f8adcd3f	\N	\N	\N	allow	read	source_sync	\N	2026-10-09 04:23:11.863146+05:30	r:employee
b716fbe9-d432-4bfd-b124-38ee5cbfda5d	\N	doc-95f9bf76e643	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:32.091196+05:30	r:finance
16a36e04-8616-4564-9115-1c8167494133	\N	doc-95f9bf76e643	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:32.092173+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
d47b5a25-5066-4c85-84c4-823d41758d9a	\N	doc-95f9bf76e643	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:32.092173+05:30	g:group-hr
e6003aa2-49ab-4569-833e-cadde5b311f0	\N	doc-95f9bf76e643	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:32.092173+05:30	r:hr
a2b860bb-5ec2-4d2a-927f-26bd52d850bf	\N	doc-95f9bf76e643	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:32.092173+05:30	r:manager
15135bc4-02f0-4078-946a-8ad0a595ee25	\N	doc-95f9bf76e643	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:32.092173+05:30	r:admin
30929bb3-0220-4cfa-9005-2968f52a350e	\N	doc-95f9bf76e643	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:32.092173+05:30	r:employee
6a2ea629-88ef-456c-b81b-f48dc69969fd	\N	doc-95f9bf76e643	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:32.092173+05:30	p:project-001
643ee7a3-b419-4a7b-b0ce-421ea80b0544	\N	doc-50690e9459bb	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.998388+05:30	r:finance
2181e51a-0f7a-455a-9ee0-064facb0ecee	\N	doc-50690e9459bb	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.998388+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
30cdd46d-84fb-4e6a-9c48-8bdd0550682a	\N	doc-50690e9459bb	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.998388+05:30	r:hr
eab4a4dd-fd92-442b-beed-d9924d6182f8	\N	doc-50690e9459bb	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.998388+05:30	r:manager
4ada1418-9406-473f-8313-f42e5482776d	\N	doc-50690e9459bb	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.998388+05:30	r:admin
05b9de71-86d0-4a7a-a2c4-731c5b35c0a1	\N	doc-50690e9459bb	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.998388+05:30	r:employee
bb4fd079-82d4-4bbf-8b9f-f74a4b4af584	\N	doc-2fef237a53e6	\N	\N	\N	allow	read	source_sync	\N	2026-10-07 13:36:34.602237+05:30	g:group-hr
4c81c442-5a4d-4964-8cac-6c2c5d5e6836	\N	doc-2fef237a53e6	\N	\N	\N	allow	read	source_sync	\N	2026-10-07 13:36:34.602237+05:30	r:manager
9a05319b-98ec-4fcc-a12e-43996f32c6a3	\N	doc-2fef237a53e6	\N	\N	\N	allow	read	source_sync	\N	2026-10-07 13:36:34.602237+05:30	r:finance
74b3479d-e9b9-4e18-8b0b-83107d490f07	\N	doc-2fef237a53e6	\N	\N	\N	allow	read	source_sync	\N	2026-10-07 13:36:34.602237+05:30	p:project-001
2dd774c4-b8a4-4895-8312-e351f6d85768	\N	doc-2fef237a53e6	\N	\N	\N	allow	read	source_sync	\N	2026-10-07 13:36:34.602237+05:30	r:hr
e2c7cda5-8fc2-421a-85fa-08a61b1fe1e1	\N	doc-2fef237a53e6	\N	\N	\N	allow	read	source_sync	\N	2026-10-07 13:36:34.602237+05:30	r:admin
f56b8363-f4b1-442a-9d5a-29fca1fd3440	\N	doc-2fef237a53e6	\N	\N	\N	allow	read	source_sync	\N	2026-10-07 13:36:34.602237+05:30	r:employee
8e530a56-971a-456c-9e36-8ad978be5e2f	\N	doc-2fef237a53e6	\N	\N	\N	allow	read	source_sync	\N	2026-10-07 13:36:34.602237+05:30	t:tenant-001
8508ceae-1928-4aff-ae8d-a2631fc4d802	\N	doc-cf0975b45d02	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:20.480924+05:30	p:project-001
c3ed9301-e313-4f78-a9d4-92924edb9fe3	\N	doc-a99b3249e8be	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.181201+05:30	r:manager
c12f7ca9-cbf1-4c0b-818a-15f64ded1d5b	\N	doc-a99b3249e8be	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.181201+05:30	r:admin
b4fb082c-8781-46cf-9e04-076edd819c4e	\N	doc-a99b3249e8be	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.181201+05:30	r:employee
e5de1059-b184-4362-8155-723eca20cfe7	\N	doc-a99b3249e8be	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.181201+05:30	r:hr
7499612e-e850-464d-94b0-903b2109c7c1	\N	doc-a99b3249e8be	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.181201+05:30	p:project-001
76fb1cfc-01d0-4c7d-ac79-b6e4f775b5cf	\N	doc-a99b3249e8be	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.181201+05:30	g:group-hr
1465dcfc-b476-48b0-8c78-4990bab5ffda	\N	doc-a99b3249e8be	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.181201+05:30	t:tenant-001
27f0b280-a81b-47fe-aad7-4d0cb5e12878	\N	doc-a99b3249e8be	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.181201+05:30	r:finance
c41797fc-a0c2-4da8-bfc9-bfb7f7758402	\N	doc-2e8e5dd3f7f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.276818+05:30	r:manager
2cd94f1d-39f5-4b08-8e34-35b5a2df5455	\N	doc-2e8e5dd3f7f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.277742+05:30	r:admin
35420b67-2a13-4d6a-bd19-7b275c724148	\N	doc-2e8e5dd3f7f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.277742+05:30	r:employee
e9549720-082f-4f73-adc1-f36fd8790042	\N	doc-2e8e5dd3f7f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.277742+05:30	r:hr
9f04606f-a589-496a-aaa1-a085eaa7984d	\N	doc-2e8e5dd3f7f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.277742+05:30	p:project-001
ba8969aa-937d-4aee-8aaf-e267a44622ee	\N	doc-2e8e5dd3f7f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.277742+05:30	g:group-hr
d75e88e9-9bbf-4d3a-afa9-79654f4d531d	\N	doc-2e8e5dd3f7f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.277742+05:30	t:tenant-001
a5ce023b-649e-4f3d-a265-486ca9f8f75e	\N	doc-2e8e5dd3f7f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.277742+05:30	r:finance
be89004d-b6e1-46e6-b73f-c62a1ef8dd6f	\N	doc-4741b651e377	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.337529+05:30	r:manager
1b22eb4f-5195-4159-9fb7-7bb16466baf0	\N	doc-4741b651e377	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.337529+05:30	r:admin
3fef1b1f-4c0f-499d-b5ab-135960420cfa	\N	doc-4741b651e377	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.337529+05:30	r:employee
0ac95590-091a-4fb7-aee3-07dbb6c56e19	\N	doc-4741b651e377	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.337529+05:30	r:hr
4cd936b0-210f-4390-9790-4d7584ec3476	\N	doc-4741b651e377	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.337529+05:30	p:project-001
09b0f729-c222-4b0c-a6b2-d9fe9b8fe068	\N	doc-4741b651e377	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.337529+05:30	g:group-hr
c4dd8fc9-cd9c-44be-9240-3070cc0cd3cd	\N	doc-4741b651e377	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.337529+05:30	t:tenant-001
efcd77e2-964a-485d-a34c-e0202577792c	\N	doc-4741b651e377	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.337529+05:30	r:finance
3c1ef550-8c63-4517-a611-22fc5e75ed5d	\N	doc-754fa9684aed	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.413414+05:30	r:manager
bf5d96d9-e3f8-4942-9ebc-f5f05233492b	\N	doc-754fa9684aed	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.413414+05:30	r:admin
9f847cbc-66a0-49bf-83bb-dc103ebf5440	\N	doc-754fa9684aed	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.413414+05:30	r:employee
5db92243-9417-4e9f-b97a-f3e65c2821f5	\N	doc-754fa9684aed	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.413414+05:30	r:hr
7438a8d1-28e4-4548-99ae-9b851a5391b7	\N	doc-754fa9684aed	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.413414+05:30	p:project-001
1338afc9-d2fe-4c05-bd6d-a8a693b5f6b4	\N	doc-754fa9684aed	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.413414+05:30	g:group-hr
84c8db37-de7b-489d-a1c5-2a2542e10a91	\N	doc-754fa9684aed	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.413414+05:30	t:tenant-001
a0dd8ada-41fb-42d2-9a8b-99a7f7cb47fb	\N	doc-754fa9684aed	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.413414+05:30	r:finance
c588a102-55da-4a43-9556-4e83032f4951	\N	doc-e57f3124b6a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.474097+05:30	r:manager
4d419302-a60b-409a-bcd6-fcc96c4a9ba1	\N	doc-e57f3124b6a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.474097+05:30	r:admin
86f2d7c2-b6da-453f-be3e-2c358378e52c	\N	doc-e57f3124b6a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.474097+05:30	r:employee
855c27ba-a8c9-4d87-89ed-bba897c132c1	\N	doc-e57f3124b6a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.474097+05:30	r:hr
a7f1fd12-e175-43a9-a716-51c1b44fd888	\N	doc-e57f3124b6a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.474097+05:30	p:project-001
4af4d2e0-9bfd-4631-b859-67b270240bd5	\N	doc-e57f3124b6a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.474097+05:30	g:group-hr
32c2f1e6-c59a-408e-af74-6be3cf8cdc80	\N	doc-e57f3124b6a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.474097+05:30	t:tenant-001
02ee64a6-d894-4e9f-a491-75e34ef2a80c	\N	doc-e57f3124b6a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.474097+05:30	r:finance
314c7b7b-6145-45b0-b848-d26f2f70bd59	\N	doc-130b39d15af6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.54094+05:30	r:manager
1e45e22c-33c6-456b-af90-9a4326d4f506	\N	doc-130b39d15af6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.54094+05:30	r:admin
6ff8dbd5-4c8a-4741-9840-f65074d0cbc2	\N	doc-130b39d15af6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.54094+05:30	r:employee
15e20c5e-de8e-41f0-85c3-ae660f7f0947	\N	doc-130b39d15af6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.54094+05:30	r:hr
c477ed28-946b-4040-bbfb-b27be528d99a	\N	doc-130b39d15af6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.54094+05:30	p:project-001
48aeb54c-0331-4b77-8f58-f8e21224699f	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	manual	\N	2026-10-07 13:40:44.398241+05:30	r:admin
0a68f9cf-0a91-47d4-9ae4-3b9528e2748f	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	manual	\N	2026-10-07 13:40:44.398241+05:30	r:manager
6ae1a797-4a02-41f1-9e08-14eb5f3443fc	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	manual	\N	2026-10-07 13:40:44.398241+05:30	r:hr
4167ba7d-71ff-4e8a-b2b7-ac2587228043	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	manual	\N	2026-10-07 13:40:44.398241+05:30	t:tenant-001
54a28c85-8f11-4e21-ab87-fcd4eb5f9436	\N	doc-27eadc26a7a2	\N	\N	\N	allow	read	manual	\N	2026-10-07 13:41:04.743929+05:30	r:admin
09ee53f9-aa88-4a0d-91c9-f8c9a730cdcf	\N	doc-27eadc26a7a2	\N	\N	\N	allow	read	manual	\N	2026-10-07 13:41:04.743929+05:30	r:hr
edc47698-d12b-4bd3-a049-11295a2ef048	\N	doc-27eadc26a7a2	\N	\N	\N	allow	read	manual	\N	2026-10-07 13:41:04.743929+05:30	t:tenant-001
f85985e5-8121-4c4a-819c-9592662e0810	\N	doc-130b39d15af6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.54094+05:30	g:group-hr
cbd4d932-c7e8-4230-939e-82475ea5181e	\N	doc-130b39d15af6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.54094+05:30	t:tenant-001
972d4215-e3b0-41db-b8b7-f4897ff7bf9c	\N	doc-130b39d15af6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.54094+05:30	r:finance
fbac6c3a-1525-4682-855b-ffe3658223e0	\N	doc-68237f22039b	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.593971+05:30	r:manager
5cd497f4-684e-4ad4-92d5-fde8fbaca578	\N	doc-68237f22039b	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.593971+05:30	r:admin
a56bba45-0442-4708-80b0-fed6142a128b	\N	doc-68237f22039b	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.593971+05:30	r:employee
d5268def-be7e-41a0-b88b-d2a15ad77bed	\N	doc-68237f22039b	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.593971+05:30	r:hr
1a2b4c4a-af62-4671-b342-1fb9b07e0995	\N	doc-68237f22039b	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.593971+05:30	p:project-001
ee576974-f0fb-48c3-9dde-164194b46b30	\N	doc-68237f22039b	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.593971+05:30	g:group-hr
f556b5c2-628f-4e8a-b008-08ec43b42585	\N	doc-68237f22039b	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.593971+05:30	t:tenant-001
8d003dfb-8356-4f94-89bc-f7a799ad9bdf	\N	doc-68237f22039b	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.593971+05:30	r:finance
5b4675a8-8e67-4e79-8d27-2e82b5fc2597	\N	doc-ef22084066f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.6584+05:30	r:manager
2e0fed60-0770-4727-80e7-5571e924dba4	\N	doc-ef22084066f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.6584+05:30	r:admin
7986a84c-b195-4ca2-8931-2744b8d56f60	\N	doc-ef22084066f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.6584+05:30	r:employee
607b77b4-421e-4693-8b93-24e0017320b8	\N	doc-ef22084066f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.6584+05:30	r:hr
cbddeee1-4f27-4a84-842a-7eb9a37dd8d4	\N	doc-ef22084066f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.6584+05:30	p:project-001
621304b4-650d-4c70-9b48-d1731a6c574a	\N	doc-ef22084066f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.6584+05:30	g:group-hr
32e75409-82f7-4c9d-b6bb-933d59d7ef61	\N	doc-ef22084066f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.6584+05:30	t:tenant-001
abd40d23-38ec-4a15-8fac-d6ecd6c1f930	\N	doc-ef22084066f3	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.6584+05:30	r:finance
12b43cc5-3922-417c-bcc7-3d86097c16bd	\N	doc-3084996f8617	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.70587+05:30	r:manager
63b2d016-d6bb-4c42-b784-28848af19e3b	\N	doc-3084996f8617	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.70587+05:30	r:admin
1f7910e0-6746-4d8e-9789-a0a1fef7a6cd	\N	doc-3084996f8617	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.70587+05:30	r:employee
014629dc-01b6-4084-a43d-602fd4867162	\N	doc-3084996f8617	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.70587+05:30	r:hr
bd8bc554-86be-4a2c-bce3-c53e45f669be	\N	doc-3084996f8617	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.70587+05:30	p:project-001
7b93b784-a27f-49e4-a5c1-f36c310c6260	\N	doc-3084996f8617	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.70587+05:30	g:group-hr
5c8e57f5-617b-4704-acf2-b8f6621936c2	\N	doc-3084996f8617	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.70587+05:30	t:tenant-001
95451653-d596-424b-98c3-81ddf9a18706	\N	doc-3084996f8617	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.70587+05:30	r:finance
9e43b2df-e3ac-4094-810d-a8c5967745bf	\N	doc-2ada98486ec4	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.750668+05:30	r:manager
ccd972d7-3c00-4082-bfc9-641b198b794f	\N	doc-2ada98486ec4	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.750668+05:30	r:admin
f3747c6a-6559-4be8-9af8-46f063676449	\N	doc-2ada98486ec4	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.750668+05:30	r:employee
daa85d0c-43ca-4aae-90bf-039eb8373e4f	\N	doc-2ada98486ec4	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.750668+05:30	r:hr
aebb0351-f473-455a-b281-83369af8d879	\N	doc-2ada98486ec4	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.750668+05:30	p:project-001
b669eff5-aa1c-467f-b1f7-5906b8da14fb	\N	doc-2ada98486ec4	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.750668+05:30	g:group-hr
19743f68-3fd7-4de0-9e66-92efcf0c9046	\N	doc-2ada98486ec4	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.750668+05:30	t:tenant-001
5e10f532-2c79-4a99-8270-705d1f7ac225	\N	doc-2ada98486ec4	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.750668+05:30	r:finance
b8aab8e3-ec8f-4e6c-a6ee-32657dd23fb4	\N	doc-3b3dd582127c	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.812338+05:30	r:manager
00688e4e-58d9-40b7-be2a-368cf8432888	\N	doc-3b3dd582127c	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.812338+05:30	r:admin
cffad905-46f8-402c-89bf-09844576457b	\N	doc-3b3dd582127c	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.812338+05:30	r:employee
eb1464ae-ac3e-4ed4-8812-573cd5d29574	\N	doc-3b3dd582127c	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.812338+05:30	r:hr
6d08e179-6de1-4092-916c-f8f172e6553f	\N	doc-3b3dd582127c	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.812338+05:30	p:project-001
7cad1350-9947-4f49-8cfb-f89fe9c78ff8	\N	doc-3b3dd582127c	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.812338+05:30	g:group-hr
6a0cf2ca-bccf-4b69-b474-ce30cbe6ab6b	\N	doc-3b3dd582127c	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.812338+05:30	t:tenant-001
fd8aff12-1b6c-4b5d-86bc-406efd028b00	\N	doc-3b3dd582127c	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.812338+05:30	r:finance
b61d31df-2d64-4a2b-8e89-bdc3b4d41d9f	\N	doc-f99607221cc6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.846516+05:30	r:manager
de549d78-c00e-4bba-98cb-0896cfdd6f01	\N	doc-f99607221cc6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.846516+05:30	r:admin
5bf3bb97-a5e9-4b41-beab-12e3e012e4ec	\N	doc-f99607221cc6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.846516+05:30	r:employee
b3d66b5c-c72d-46d5-9319-6fb6c5ca8990	\N	doc-f99607221cc6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.846516+05:30	r:hr
b123ded2-6285-4381-b941-e32fc6b29ed2	\N	doc-f99607221cc6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.846516+05:30	p:project-001
b62f491d-a4fb-4a35-890f-0b1e4b0bb83d	\N	doc-f99607221cc6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.846516+05:30	g:group-hr
652f7651-0bd5-4c97-9d40-6e70e64edf66	\N	doc-f99607221cc6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.846516+05:30	t:tenant-001
8f9e909d-9128-43a3-b716-ebce690747f3	\N	doc-f99607221cc6	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.846516+05:30	r:finance
a6d20717-2868-43eb-ada0-7731ca72531b	\N	doc-21379031a248	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.884676+05:30	r:manager
9a24a15f-ff39-4d8f-9088-25c848d3bc16	\N	doc-21379031a248	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.884676+05:30	r:admin
d8a42c8a-1975-43e0-8088-75f87f97376f	\N	doc-21379031a248	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.885189+05:30	r:employee
e72ac168-ee26-4fcc-ab10-e0fd07d03320	\N	doc-21379031a248	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.885189+05:30	r:hr
31b68a9c-8f5a-4e58-af07-7d6b2b20c613	\N	doc-21379031a248	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.885189+05:30	p:project-001
a74454e3-9997-41fa-9ccc-b719f8f7b153	\N	doc-21379031a248	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.885189+05:30	g:group-hr
3c20b7cb-f72f-40cb-b24a-a6770b848c5d	\N	doc-21379031a248	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.885189+05:30	t:tenant-001
143489f5-4196-427e-ac53-84f70c1f985e	\N	doc-21379031a248	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.885189+05:30	r:finance
fc931905-83bc-4ec9-bbfc-5b78538f3105	\N	doc-fd7fd7ba8702	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.932137+05:30	r:manager
c9227492-9764-490b-ab4d-daa2535333b2	\N	doc-fd7fd7ba8702	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.932723+05:30	r:admin
91182cc1-b27e-462a-b46d-a070b7b4715b	\N	doc-fd7fd7ba8702	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.932723+05:30	r:employee
7deff8ad-6bad-451c-83fa-ca0b09c59304	\N	doc-fd7fd7ba8702	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.932723+05:30	r:hr
ab115bd9-83f7-4dcd-bb75-fd7f4149e72d	\N	doc-fd7fd7ba8702	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.932723+05:30	p:project-001
c993f831-9fa0-430d-a6d3-bff19ba7983b	\N	doc-fd7fd7ba8702	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.932723+05:30	g:group-hr
78178254-82f2-478e-af80-5dfb08e146f2	\N	doc-fd7fd7ba8702	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.932723+05:30	t:tenant-001
359dc946-58ca-4523-a5b2-8de2f25a60ee	\N	doc-fd7fd7ba8702	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.932723+05:30	r:finance
ead5b44f-a160-4b5f-96fe-edab97dfbcef	\N	doc-f4de4672f657	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.980411+05:30	r:manager
2b83088f-bf6d-41b9-a4e8-8556278fe792	\N	doc-f4de4672f657	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.980411+05:30	r:admin
0e1e1ef0-4d6a-4d2f-82a9-932b5676085e	\N	doc-f4de4672f657	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.980411+05:30	r:employee
197b2e3c-657d-416c-b238-5346d8bed1bb	\N	doc-f4de4672f657	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.980411+05:30	r:hr
295c5647-ab85-473a-ac58-8285de32f411	\N	doc-f4de4672f657	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.980411+05:30	p:project-001
620de8d5-0964-41d9-bafc-f60e23391507	\N	doc-f4de4672f657	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.980411+05:30	g:group-hr
c471d4ee-5a1e-4ba0-af40-d9bda7c5a87c	\N	doc-f4de4672f657	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.980411+05:30	t:tenant-001
c40197bc-a534-40de-9a9c-f33983f432c8	\N	doc-f4de4672f657	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:01.980411+05:30	r:finance
4de001b7-690f-4125-9606-7ac4e09523ac	\N	doc-27eadc26a7a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.055619+05:30	r:manager
98cc445f-1696-4f02-8827-c3820b97a9f9	\N	doc-27eadc26a7a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.055619+05:30	r:admin
3b4323c0-cbed-4ac8-b5bc-62081ff468cd	\N	doc-27eadc26a7a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.055619+05:30	r:employee
fa19cb52-5441-4609-9bdb-45c7a7ce559c	\N	doc-27eadc26a7a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.055619+05:30	r:hr
76b365b8-b9f1-4d5f-b486-bae1acaa3a12	\N	doc-27eadc26a7a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.055619+05:30	p:project-001
1e1bc6bc-05a7-44ec-93e1-353e6524e59d	\N	doc-27eadc26a7a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.055619+05:30	g:group-hr
d6bab27a-4690-4c25-b423-deca322ed444	\N	doc-27eadc26a7a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.055619+05:30	t:tenant-001
bfe5dbb7-4d6a-44d6-9ad7-7138a3d8ad83	\N	doc-27eadc26a7a2	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.055619+05:30	r:finance
0f683d68-ad31-4bcb-8b4e-7880bb0d8c1e	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.101208+05:30	r:manager
5663aab4-0859-40de-a47b-575a571ddb85	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.101792+05:30	r:admin
bcd55a41-5192-4b37-b3cf-bc801f8ae8e3	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.101792+05:30	r:employee
a810c887-151e-421d-87d0-51ade255cbea	\N	doc-4f328576121e	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.092551+05:30	r:finance
50f52b5f-f7d4-4747-99d2-3c0f48aba8b0	\N	doc-4f328576121e	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.092551+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
ad1112a2-d9dd-4bbe-92f8-74e8ad561a41	\N	doc-4f328576121e	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.092551+05:30	r:hr
62d17d0c-1545-45cb-ad20-e872269c32af	\N	doc-4f328576121e	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.092551+05:30	r:manager
b052a189-12dc-47c2-940b-eecdfe836edb	\N	doc-4f328576121e	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.092551+05:30	r:admin
d25d05e6-27e4-4ddb-b0a5-ef996b003ffe	\N	doc-4f328576121e	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:06.092551+05:30	r:employee
343359d8-244a-48e9-b3a8-1e1e50e20508	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.101792+05:30	r:hr
00e4868f-3c61-4672-ba98-5e016c0715eb	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.101792+05:30	p:project-001
7836bd95-f99f-4336-9177-d88f124e18fa	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.101792+05:30	g:group-hr
c9259a60-6809-4489-8c96-c5dae395427c	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.101792+05:30	t:tenant-001
1f2caae4-195c-400b-b695-a4fb6b05d634	\N	doc-f34d3b0e0c4d	\N	\N	\N	allow	read	source_sync	\N	2026-10-08 14:54:02.101792+05:30	r:finance
a7ebfac4-6f82-455e-aed9-408866a10b86	\N	doc-de573a503f6d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:44.839415+05:30	r:manager
24842218-0216-46fb-b3fb-087432725b37	\N	doc-de573a503f6d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:44.839415+05:30	r:admin
af372a6a-1c30-4d3f-a874-fddb676d3a66	\N	doc-de573a503f6d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:44.839415+05:30	r:hr
4d26f83b-60ba-491c-9988-5027638e547b	\N	doc-ff2f2247df35	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.923642+05:30	r:finance
0e43ae70-31f0-4dcc-a347-7f33ccb4f9b2	\N	doc-ff2f2247df35	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.923642+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
c9ecdb6e-8099-433e-96f6-ca723e2fd01a	\N	doc-ff2f2247df35	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.923642+05:30	r:hr
4ecce1af-925a-4e60-888d-b70852deca7e	\N	doc-ff2f2247df35	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.923642+05:30	r:manager
5511adc3-28cd-45f3-aab4-1e4bc5deb494	\N	doc-ff2f2247df35	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.923642+05:30	r:admin
3b2ebdc6-3ad2-466f-a435-f35d4abe5747	\N	doc-ff2f2247df35	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:08:05.923642+05:30	r:employee
43bc08df-53a3-417a-b4f4-00af193f3e59	\N	doc-de573a503f6d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:44.839415+05:30	t:tenant-001
a1a4066a-4094-46de-ba09-278d3ef1b6dd	\N	doc-de573a503f6d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:44.839415+05:30	r:finance
3926cd5b-ee90-434b-a676-ce0e25644d55	\N	doc-de573a503f6d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:44.839415+05:30	p:project-001
3cff2bd0-a249-4a8e-9c88-b9daeed5c46b	\N	doc-de573a503f6d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:44.839415+05:30	r:employee
24c2fd16-d8f4-4069-9f49-2a4c3042811e	\N	doc-de573a503f6d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:44.839415+05:30	g:group-hr
9508955b-8d86-4b36-97ae-6e5c92396e62	\N	doc-ab5c26d1ac91	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:08.541472+05:30	r:finance
c2be70c7-09f5-419c-b82f-254d5ae1636d	\N	doc-ab5c26d1ac91	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:08.541472+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
3a85f145-774e-46a0-b896-19d373689f88	\N	doc-ab5c26d1ac91	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:08.542486+05:30	g:group-hr
1c32be01-c9db-48cb-b93d-4f6665a7c06a	\N	doc-ab5c26d1ac91	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:08.542486+05:30	r:hr
3db199fb-ba53-47c2-bfef-57a4c54b44b1	\N	doc-ab5c26d1ac91	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:08.542486+05:30	r:manager
44ee4b12-ff1f-4b7b-bb01-bd4801e25141	\N	doc-ab5c26d1ac91	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:08.542486+05:30	r:admin
9c981adf-7f0b-4a6e-8d8a-900e428739e5	\N	doc-ab5c26d1ac91	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:08.542486+05:30	r:employee
c61d7b23-15b1-4b48-82c4-4e31d712fe78	\N	doc-ab5c26d1ac91	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:08.542486+05:30	p:project-001
e30eb9ef-cd4c-4f42-83ef-646d6a05fa6a	\N	doc-3d054e40aba7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:12.098101+05:30	r:finance
6c684ff0-53ef-4681-bcba-7a3bdd657697	\N	doc-3d054e40aba7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:12.098101+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
80b8a958-4253-4e4a-9090-10bf720ee484	\N	doc-3d054e40aba7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:12.098101+05:30	g:group-hr
5733abf2-4fd5-44ee-aa7e-ac3a2ba4e437	\N	doc-3d054e40aba7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:12.098101+05:30	r:hr
880101cf-8cdb-4354-9ef3-4966ef69cacb	\N	doc-3d054e40aba7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:12.098101+05:30	r:manager
423d3031-bfd8-4c10-9233-b44bbe4d27b1	\N	doc-3d054e40aba7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:12.098101+05:30	r:admin
084f5d90-da76-4821-a009-1276b2de03d2	\N	doc-3d054e40aba7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:12.098101+05:30	r:employee
54dcc9ae-46f5-4968-b8fe-69f89496dd19	\N	doc-3d054e40aba7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:12.098101+05:30	p:project-001
736003f4-c043-464b-af36-5d5cf947bcfa	\N	doc-d6402dc16e20	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:16.004516+05:30	r:finance
54bef79c-4041-42e7-ad37-58114afdeda7	\N	doc-d6402dc16e20	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:16.004516+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
8c9acd5f-9029-44b6-82a2-3bf5884f054a	\N	doc-d6402dc16e20	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:16.004516+05:30	g:group-hr
6cefeb21-0ebd-41cf-adf3-f78b51a39967	\N	doc-d6402dc16e20	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:16.004516+05:30	r:hr
87ddf03c-013c-4901-bf7a-e94ebd94334a	\N	doc-d6402dc16e20	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:16.004516+05:30	r:manager
2497af6d-ce5d-4138-afc2-47879cec18b9	\N	doc-d6402dc16e20	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:16.004516+05:30	r:admin
aa9ac40b-842a-4243-94ed-b23da7f21c6f	\N	doc-d6402dc16e20	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:16.004516+05:30	r:employee
5e3e7c4d-9f33-4cf5-88c6-7442a003ef9b	\N	doc-f5e24b39a009	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:23:42.812483+05:30	r:finance
3bfe90db-2f99-402a-a6d5-f8f60a4172d4	\N	doc-f5e24b39a009	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:23:42.812483+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
ddbd01c5-1595-44a8-b36d-e9f7be98265e	\N	doc-bd628377481b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:45.734775+05:30	r:manager
bab0a467-eb25-453f-99b4-060b77cd1dea	\N	doc-bd628377481b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:45.734775+05:30	r:admin
8cc5e5b9-63f0-42eb-aa48-7e986acfe568	\N	doc-bd628377481b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:45.734775+05:30	r:hr
83da7762-9ba6-4f20-bff6-3b2f8a7bb85b	\N	doc-bd628377481b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:45.734775+05:30	t:tenant-001
92117478-82ee-4d7c-a440-48d81ceb5529	\N	doc-bd628377481b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:45.734775+05:30	r:finance
22f34e1f-17e6-45db-b457-5df9d971fe27	\N	doc-bd628377481b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:45.734775+05:30	p:project-001
2e43d71d-5fe0-4886-aebd-f9ef123bd2f0	\N	doc-bd628377481b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:45.734775+05:30	r:employee
cd58c24b-e58a-4d37-ada6-e481b74b18ac	\N	doc-bd628377481b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:45.734775+05:30	g:group-hr
82e6f3c2-82e1-457b-ade7-6bc8b7cbcec9	\N	doc-f5e24b39a009	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:23:42.812483+05:30	r:hr
d9c49ab7-f67d-44e9-a553-12321c14af4d	\N	doc-f5e24b39a009	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:23:42.812483+05:30	r:manager
6026fcba-07c8-4ea1-bff2-da9207e0ee0f	\N	doc-f5e24b39a009	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:23:42.813482+05:30	r:admin
14be8987-ef9a-46f3-8605-fb96601346e2	\N	doc-f5e24b39a009	\N	\N	\N	allow	read	manual	\N	2026-10-10 11:23:42.813482+05:30	r:employee
eb92a316-8f82-420b-8b7a-791350095fa5	\N	doc-f5e24b39a009	\N	\N	\N	deny	read	manual	\N	2026-10-10 11:23:42.813482+05:30	u:purvahead@apex.com
5d54b52f-18ce-4db7-9348-147765cd7cbc	\N	doc-becad9a82359	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.362214+05:30	r:manager
8f57edbe-f0a5-4176-bf41-a57d7f2a178b	\N	doc-becad9a82359	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.362214+05:30	r:admin
9c08e865-a0c4-4c12-8fdb-a68fbddc84a6	\N	doc-becad9a82359	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.362214+05:30	r:hr
ced95b6b-e472-4713-9ef3-404bd67cc066	\N	doc-becad9a82359	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.362214+05:30	t:tenant-001
6522a6ef-bbc0-444e-8ddf-24a2101de3b1	\N	doc-becad9a82359	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.362214+05:30	r:finance
5ca0ca71-f622-47ab-a474-bb97b44150ad	\N	doc-becad9a82359	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.362214+05:30	p:project-001
f257d9be-6b48-4352-9d30-a35217530edc	\N	doc-becad9a82359	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.362214+05:30	r:employee
19841dcd-48b0-49d3-89b4-9d620d69a162	\N	doc-becad9a82359	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.362214+05:30	g:group-hr
418dca8a-7607-42d1-848c-defb8af56079	\N	doc-a2d6def96248	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.458869+05:30	r:manager
dd5b7954-522c-4fb8-a4db-a8e2ab5c1040	\N	doc-a2d6def96248	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.458869+05:30	r:admin
9a3c98cc-5d93-43e3-8817-9eb36d25562b	\N	doc-a2d6def96248	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.458869+05:30	r:hr
4d898628-1ca6-49d6-b38e-bf99d37fc681	\N	doc-a2d6def96248	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.458869+05:30	t:tenant-001
a7d3434f-a205-4169-b2cb-594a10c32494	\N	doc-a2d6def96248	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.458869+05:30	r:finance
a5de33eb-769e-45b6-9317-5605a66bdb2e	\N	doc-a2d6def96248	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.458869+05:30	p:project-001
30df32d1-c8ee-4dd8-b182-08060e2bdea6	\N	doc-a2d6def96248	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.458869+05:30	r:employee
4efd5221-4d28-4888-a427-446f2443e791	\N	doc-a2d6def96248	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.458869+05:30	g:group-hr
f48e3d07-587f-4dff-b0b8-cf2322310ae1	\N	doc-9a4395663625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.565847+05:30	r:manager
53f47b06-18fe-4072-87e7-b5bdcc6a16fb	\N	doc-9a4395663625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.565847+05:30	r:admin
ccd16df8-2c66-423e-a831-3530ccedbaa2	\N	doc-9a4395663625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.565847+05:30	r:hr
548cc688-4aaf-41f7-9a37-08fc98901772	\N	doc-9a4395663625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.565847+05:30	t:tenant-001
e6a164b1-25fc-4591-9c51-fcf86bac7e8c	\N	doc-9a4395663625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.565847+05:30	r:finance
130b4cb7-c37e-4b10-8a1b-1b258aa92431	\N	doc-9a4395663625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.565847+05:30	p:project-001
de8c725c-a169-4b7f-ba51-c88b2a6baead	\N	doc-9a4395663625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.565847+05:30	r:employee
38f362b5-7dc6-437e-8649-67a9047a9aba	\N	doc-9a4395663625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.565847+05:30	g:group-hr
4d6c4291-6c6b-4b2d-b06b-da213af05fcb	\N	doc-37cea547ae24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.684583+05:30	r:manager
f17216d6-bc32-4055-8ca5-a1114f979c8d	\N	doc-37cea547ae24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.684583+05:30	r:admin
6398ffdd-2804-4610-aae6-439457cf74ae	\N	doc-37cea547ae24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.684583+05:30	r:hr
3b3783ba-fa65-4494-b6a1-5eb8ecaa9a43	\N	doc-37cea547ae24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.684583+05:30	t:tenant-001
5c56684b-3bdb-475b-8a2e-e4ba8d423fec	\N	doc-37cea547ae24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.684583+05:30	r:finance
800a622f-b934-453a-8408-627bcb5493e6	\N	doc-37cea547ae24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.684583+05:30	p:project-001
b9317251-8f69-41b2-98cd-a01842614d06	\N	doc-37cea547ae24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.684583+05:30	r:employee
1c1d879f-4a65-40cc-bb75-495621bf1ff5	\N	doc-37cea547ae24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.684583+05:30	g:group-hr
c7d25895-9fd3-4484-a611-1338d15db85e	\N	doc-03b90406eca2	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.767365+05:30	r:manager
019d8961-e800-43ea-ba1e-8b3337a5df0a	\N	doc-03b90406eca2	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.768365+05:30	r:admin
d5843709-005c-40ef-a628-56a1858f61d7	\N	doc-03b90406eca2	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.768365+05:30	r:hr
789a262d-0434-47aa-8844-2ca9cab4ad62	\N	doc-03b90406eca2	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.768365+05:30	t:tenant-001
31f6b9e6-34ad-4fc4-9de3-b51a9b380590	\N	doc-03b90406eca2	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.768365+05:30	r:finance
c55ba9b3-4aec-4d58-97d3-d70f546705c4	\N	doc-03b90406eca2	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.768365+05:30	p:project-001
307d0c9f-2d6d-44bd-b603-33e1aa1ae6eb	\N	doc-03b90406eca2	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.768365+05:30	r:employee
54381dce-f98e-43ae-9911-f5856aa2901b	\N	doc-03b90406eca2	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.768365+05:30	g:group-hr
e8b1b9b9-c311-4807-9117-1b908606b0a0	\N	doc-5e4f6cd7d179	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.87791+05:30	r:manager
5a52444d-119e-427e-b3fa-a2288dc27fea	\N	doc-5e4f6cd7d179	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.87791+05:30	r:admin
1e9bd085-76a0-4b8d-abba-b95d403e6075	\N	doc-5e4f6cd7d179	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.87791+05:30	r:hr
e3ef319a-1930-4162-9be1-361e201b60f0	\N	doc-5e4f6cd7d179	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.87791+05:30	t:tenant-001
b13b9b09-2834-486a-b3f8-62d1511138dd	\N	doc-5e4f6cd7d179	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.87791+05:30	r:finance
611c9647-8186-4cc1-91dd-e68ef7995ad5	\N	doc-5e4f6cd7d179	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.87791+05:30	p:project-001
416da701-4f0e-4c77-87ae-bd6fc52004f3	\N	doc-5e4f6cd7d179	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.87791+05:30	r:employee
0f4757a6-e74f-4d10-8ac3-7f1c1adeb941	\N	doc-5e4f6cd7d179	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.87791+05:30	g:group-hr
7f6eac3f-ad3a-45c5-9418-3f4ac61213e8	\N	doc-43c0cbab0d45	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.983736+05:30	r:manager
3aabf6e5-c610-4dd2-8030-e9120020212a	\N	doc-43c0cbab0d45	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.983736+05:30	r:admin
9259464e-4777-4341-8a8d-0d371bcf2b2c	\N	doc-43c0cbab0d45	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.983736+05:30	r:hr
4662e255-c888-4eff-b8b2-24e79bf4da34	\N	doc-43c0cbab0d45	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.983736+05:30	t:tenant-001
0b774fe7-77a9-4896-981b-3492d283708e	\N	doc-43c0cbab0d45	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.983736+05:30	r:finance
98efec4e-974f-4e15-9649-60ebebfcfbe3	\N	doc-43c0cbab0d45	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.983736+05:30	p:project-001
1c451a6e-5cf6-488f-b4a7-9f386478e334	\N	doc-43c0cbab0d45	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.983736+05:30	r:employee
e1bd169c-143a-4fec-87d4-7a3aa4cbe1f2	\N	doc-43c0cbab0d45	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:46.983736+05:30	g:group-hr
fd21f0bb-d7e4-42a7-9fb4-c368463a7f63	\N	doc-eb33be1c8687	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.101826+05:30	r:manager
318fdc5a-cac2-477d-bf71-500eabaf7c6d	\N	doc-eb33be1c8687	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.101826+05:30	r:admin
0dc6bc48-a1f9-4c6c-a56d-c6edb608fcdd	\N	doc-eb33be1c8687	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.101826+05:30	r:hr
f3a27073-f541-4a50-8a3e-d009caa54256	\N	doc-eb33be1c8687	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.101826+05:30	t:tenant-001
d46a08e1-daa9-4c20-a34c-25bb12150bf6	\N	doc-eb33be1c8687	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.101826+05:30	r:finance
50c452e4-83bd-47db-9d1c-302d137c5fc0	\N	doc-eb33be1c8687	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.101826+05:30	p:project-001
8ddaad66-691a-49f8-b021-976624a966c3	\N	doc-eb33be1c8687	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.101826+05:30	r:employee
34704eef-ac2f-4638-81d2-79b546165cc8	\N	doc-eb33be1c8687	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.101826+05:30	g:group-hr
67003c98-3085-41d6-812c-8440fa9ce120	\N	doc-0718297b71e4	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.198758+05:30	r:manager
9eef59ae-a2a9-4a27-913f-1432446623fa	\N	doc-0718297b71e4	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.198758+05:30	r:admin
8e4343b3-eec8-496d-94cf-c3c18ad3c7ee	\N	doc-0718297b71e4	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.198758+05:30	r:hr
c9a59b79-b4f4-45dd-8dc0-4b5e54ae4352	\N	doc-0718297b71e4	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.198758+05:30	t:tenant-001
eadd7013-8bf9-4f16-9bf9-e3ba6041f877	\N	doc-0718297b71e4	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.198758+05:30	r:finance
0b955a54-f7c3-44cd-9880-74e8bd531e82	\N	doc-0718297b71e4	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.198758+05:30	p:project-001
d8889b51-d551-4411-a118-e19c0efa75b3	\N	doc-0718297b71e4	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.198758+05:30	r:employee
6b484fdd-ff91-40a4-967b-ab52819a38a1	\N	doc-0718297b71e4	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.198758+05:30	g:group-hr
894f1160-17ee-4a63-b585-7761491f055f	\N	doc-0a51cdb40625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.285905+05:30	r:manager
c2f00df7-88c1-46c1-ba00-3f7cf033178a	\N	doc-0a51cdb40625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.285905+05:30	r:admin
7b4a4a3c-756b-4d43-aafb-5e8d704bde5c	\N	doc-0a51cdb40625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.285905+05:30	r:hr
c97e4e75-a0d6-4cd1-906e-e175f021cdb7	\N	doc-0a51cdb40625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.285905+05:30	t:tenant-001
d1bc3bef-5419-45bd-ab59-e7854fcca98e	\N	doc-0a51cdb40625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.285905+05:30	r:finance
4b373521-64b2-4422-8171-1d59db44e03a	\N	doc-0a51cdb40625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.285905+05:30	p:project-001
028bff23-d1a0-4c3b-bfb2-eeb7fed6694b	\N	doc-0a51cdb40625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.285905+05:30	r:employee
f68f2f29-6cd5-4395-8b5c-57c7f44e5803	\N	doc-0a51cdb40625	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.285905+05:30	g:group-hr
b532570e-fbc9-44d1-ae5f-dd4348e067d0	\N	doc-fad3ce481e4b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.380701+05:30	r:manager
40ab60b6-4cdb-4605-ae88-7380dd0b28b5	\N	doc-fad3ce481e4b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.380701+05:30	r:admin
3adde5c6-2b24-4d93-b874-a08cee6c582e	\N	doc-fad3ce481e4b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.380701+05:30	r:hr
88558b75-5be1-412a-bdf7-7d247a312875	\N	doc-fad3ce481e4b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.380701+05:30	t:tenant-001
c6500c78-fb8d-4552-80f7-0de0eebf5b07	\N	doc-fad3ce481e4b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.380701+05:30	r:finance
7ec2857c-e33e-44e9-b251-5730a1640669	\N	doc-fad3ce481e4b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.380701+05:30	p:project-001
776e797d-5587-41fc-89e7-690be3a04d9e	\N	doc-fad3ce481e4b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.380701+05:30	r:employee
79b79913-342b-49bf-a293-6a5e1aa93701	\N	doc-fad3ce481e4b	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.380701+05:30	g:group-hr
e8b2a16c-78fa-414f-9e30-1a5110251bdb	\N	doc-8405e29cdc24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.495169+05:30	r:manager
4107a8c7-0baa-45ef-ad45-7a8c91b1bbc8	\N	doc-8405e29cdc24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.495169+05:30	r:admin
20b98911-8005-431b-879c-4d174cc27ebf	\N	doc-8405e29cdc24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.495169+05:30	r:hr
937fa38a-d740-4b8e-9a39-a84353062121	\N	doc-8405e29cdc24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.495169+05:30	t:tenant-001
5eac60e1-e39c-4119-81d5-e11c82d4a9df	\N	doc-8405e29cdc24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.495169+05:30	r:finance
398e6551-6380-495c-bd91-9c7217370916	\N	doc-8405e29cdc24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.495169+05:30	p:project-001
e1d3aa13-9c7b-4480-9b04-a5273400be7a	\N	doc-8405e29cdc24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.495169+05:30	r:employee
9951e508-37ca-4a86-93bb-dbc1278ee608	\N	doc-8405e29cdc24	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.495169+05:30	g:group-hr
2fab7ad7-db83-49fc-9427-0f372ba8e44d	\N	doc-b02ac5215dad	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.579905+05:30	r:manager
0a2aeb84-0c45-4769-951e-cc5a26cc0478	\N	doc-b02ac5215dad	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.579905+05:30	r:admin
466414b7-e606-45a9-a434-bc0024e7636b	\N	doc-b02ac5215dad	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.579905+05:30	r:hr
f2d03698-1a5f-4a43-8d74-2c3de1177e22	\N	doc-b02ac5215dad	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.579905+05:30	t:tenant-001
af8bca9a-573b-4e55-80fd-bd4b869a32fc	\N	doc-b02ac5215dad	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.579905+05:30	r:finance
904a986a-c184-4c0a-b31f-445c73e3a5d4	\N	doc-b02ac5215dad	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.579905+05:30	p:project-001
a8cbf2cd-cc59-4b2e-a7fe-5b25d2fb8ab2	\N	doc-b02ac5215dad	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.579905+05:30	r:employee
e3729944-e094-4c28-913d-4ebad8b56bb5	\N	doc-b02ac5215dad	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.579905+05:30	g:group-hr
b37599a7-0fac-4e86-af23-21a2dd593c6a	\N	doc-e9cdba142890	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.682028+05:30	r:manager
4c4b90ff-d150-4651-8c45-d9aef3a02812	\N	doc-e9cdba142890	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.683027+05:30	r:admin
f71c439f-d43d-4fda-82bb-2e3f3210c785	\N	doc-e9cdba142890	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.683027+05:30	r:hr
ee33a228-ad24-41f6-8a78-882d16e62b87	\N	doc-e9cdba142890	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.683027+05:30	t:tenant-001
86c1d581-f21a-4b08-bfdb-3c01d3016c0b	\N	doc-e9cdba142890	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.683027+05:30	r:finance
c7c013d6-9aff-4863-8b2e-a164f7c608e2	\N	doc-e9cdba142890	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.683027+05:30	p:project-001
d339f211-00ef-43ab-a449-8e706eac1f2a	\N	doc-e9cdba142890	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.683027+05:30	r:employee
90ed11b3-5e60-402c-acce-fc2701b9986f	\N	doc-e9cdba142890	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.683027+05:30	g:group-hr
03eb546e-ec22-462a-8068-93b9353a78dd	\N	doc-a453aa814971	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.789734+05:30	r:manager
2b87f31d-8529-4eed-acb2-75312a0bef1c	\N	doc-a453aa814971	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.789734+05:30	r:admin
fb973be9-d24d-4424-9e00-c71a1b609b6b	\N	doc-a453aa814971	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.789734+05:30	r:hr
374302d0-f09a-4944-b0ba-1091da391996	\N	doc-a453aa814971	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.789734+05:30	t:tenant-001
9c80e5db-f88f-49ff-8bf3-bef6162bfab1	\N	doc-a453aa814971	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.789734+05:30	r:finance
43c8e208-17d6-42f3-a7ff-3074318bd81a	\N	doc-a453aa814971	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.789734+05:30	p:project-001
cb0c4010-f907-4073-b326-84c2d84db8af	\N	doc-a453aa814971	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.789734+05:30	r:employee
d4bd0788-476d-461a-b8ea-8894c3720089	\N	doc-a453aa814971	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 10:34:47.789734+05:30	g:group-hr
f3481673-b60c-4f18-9649-92c51f8604ff	\N	doc-f86ce675b533	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:56.846249+05:30	r:finance
71bf60ac-446a-4f26-98c2-1d5222cec37a	\N	doc-f86ce675b533	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:56.846249+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
3e01a322-891a-4145-992e-1e058931abbb	\N	doc-f86ce675b533	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:56.846249+05:30	g:group-hr
4e17f6f0-8992-4c9d-b9be-ad71a6e8406b	\N	doc-f86ce675b533	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:56.846249+05:30	r:hr
9c7b6b88-fcf8-484e-9a05-e75394157565	\N	doc-f86ce675b533	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:56.846249+05:30	r:manager
bd70b03b-d78c-4c12-850a-7b3adafe5551	\N	doc-f86ce675b533	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:56.846249+05:30	r:admin
1126a966-c57c-49a7-80bb-5bd2ebb8070d	\N	doc-f86ce675b533	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:56.846249+05:30	r:employee
18ffe90f-edb8-453c-952f-877ca186f5d0	\N	doc-f86ce675b533	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:56.846249+05:30	p:project-001
81d76965-6337-4c53-83d0-fce3938b3bca	\N	doc-d6402dc16e20	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:16.004516+05:30	p:project-001
1e78bc9c-ecc6-40e4-b2e6-f9845c81d9e0	\N	doc-cf0975b45d02	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:20.480924+05:30	r:finance
a2cffe34-e48f-45d0-a851-a30da2c3c6f0	\N	doc-cf0975b45d02	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:20.480924+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
cbebcd63-df52-42a3-b45f-199976bb640f	\N	doc-cf0975b45d02	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:20.480924+05:30	g:group-hr
fdccfec7-0964-494c-94a3-b10aec5d4251	\N	doc-cf0975b45d02	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:20.480924+05:30	r:hr
6ea80b2d-8d01-472c-8d9e-8b33a3f8029f	\N	doc-cf0975b45d02	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:20.480924+05:30	r:manager
fe20d27c-6547-49a3-907a-d0777bc648c1	\N	doc-cf0975b45d02	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:20.480924+05:30	r:admin
75752b66-10cd-4d2e-9f00-dd7c8cfcadea	\N	doc-cf0975b45d02	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:03:20.480924+05:30	r:employee
987c9af3-51ab-4b23-bbfe-254d01efea92	\N	doc-6c4fc0bf754c	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:37.783704+05:30	r:finance
3dfb05d5-49ef-4d00-ac73-955b82d3ed7f	\N	doc-6c4fc0bf754c	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:37.783704+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
f0697e94-fe9a-4ea0-b6b3-a9e3d088b3e0	\N	doc-6c4fc0bf754c	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:37.783704+05:30	g:group-hr
39818d2f-8714-411b-a6dd-92a127aa646a	\N	doc-6c4fc0bf754c	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:37.783704+05:30	r:hr
f6bc68aa-ce69-460a-9d9f-1d859459dfcd	\N	doc-6c4fc0bf754c	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:37.783704+05:30	r:manager
6d8f21a6-c71b-46a9-a66c-621835b8a503	\N	doc-6c4fc0bf754c	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:37.783704+05:30	r:admin
e96ac796-5b87-4a8a-ae88-12a198d6fc71	\N	doc-6c4fc0bf754c	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:37.783704+05:30	r:employee
a7823171-81af-4e97-bd5e-41f7e09ce431	\N	doc-6c4fc0bf754c	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:37.783704+05:30	p:project-001
e11a3cfe-010b-4aec-b73a-43db5c687367	\N	doc-a8180f3bb43d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:41.493893+05:30	r:finance
8581f3aa-f6f5-4aa2-b4c7-8cb5f373d176	\N	doc-a8180f3bb43d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:41.494913+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
bd65e834-2370-42f1-9fb8-e697251270a5	\N	doc-a8180f3bb43d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:41.494913+05:30	g:group-hr
2091e83e-b20d-4908-bc0d-bcbc7b60632b	\N	doc-a8180f3bb43d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:41.494913+05:30	r:hr
64d5b379-d1b4-4459-ab60-3fbd1fec96e3	\N	doc-a8180f3bb43d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:41.494913+05:30	r:manager
bd9f4396-70cc-4f45-a756-1937fbe253d9	\N	doc-a8180f3bb43d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:41.494913+05:30	r:admin
863eca8e-e540-4b39-9fe0-6f7717508914	\N	doc-a8180f3bb43d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:41.494913+05:30	r:employee
ac6994e7-057c-4b0e-8112-f075aa6f20ec	\N	doc-a8180f3bb43d	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:41.494913+05:30	p:project-001
1ef37ab0-0aa9-438c-8d32-c4e06572b033	\N	doc-24f027b6f4a7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:45.412227+05:30	r:finance
fa0233c6-3641-4dd6-9655-689724c9170a	\N	doc-24f027b6f4a7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:45.412227+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
eac244d0-0f64-443b-b598-96cef10e85c0	\N	doc-24f027b6f4a7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:45.412227+05:30	g:group-hr
5ea6688b-87ed-45fd-966f-f6385beb05d0	\N	doc-24f027b6f4a7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:45.412227+05:30	r:hr
84b6cd6a-409d-4920-8e84-c858f96ae4e6	\N	doc-24f027b6f4a7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:45.412227+05:30	r:manager
5b922a94-11f8-4617-b42b-594d946dadad	\N	doc-24f027b6f4a7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:45.412227+05:30	r:admin
a88815d4-02a8-4f8f-93fb-abff28c05032	\N	doc-24f027b6f4a7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:45.412227+05:30	r:employee
21040c64-7262-4c49-9d8c-594582a026d2	\N	doc-24f027b6f4a7	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:45.412227+05:30	p:project-001
8f378940-927b-4eeb-bd8e-cfcdfd7ac08a	\N	doc-e8e98b8c83a3	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:49.457773+05:30	r:finance
589fdcfc-02a9-49f0-aaa1-b6eb1e876e78	\N	doc-e8e98b8c83a3	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:49.457773+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
ea0cfc5d-6892-4778-886a-d0aad70604e5	\N	doc-e8e98b8c83a3	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:49.457773+05:30	g:group-hr
4445110a-e0c0-4fff-b35e-e73346303ed5	\N	doc-e8e98b8c83a3	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:49.457773+05:30	r:hr
713188ac-14ef-4f5d-bc82-9b81cd260ef8	\N	doc-e8e98b8c83a3	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:49.457773+05:30	r:manager
029180cc-5190-4a07-a863-8a086ffb39b5	\N	doc-e8e98b8c83a3	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:49.457773+05:30	r:admin
141b6bdd-d7f0-42ff-9950-9a655b77974c	\N	doc-e8e98b8c83a3	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:49.457773+05:30	r:employee
ae1b9384-8b01-4bf0-9144-f152563e5c32	\N	doc-e8e98b8c83a3	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:49.457773+05:30	p:project-001
00bedd59-df41-4d78-b913-3ed3521574b3	\N	doc-75f8446029de	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:53.177808+05:30	r:finance
e459b792-b89a-407b-9f99-ebf8e0ca4ce2	\N	doc-75f8446029de	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:53.178818+05:30	t:df672f52-b432-45f1-b1a6-4b4b78e23065
218c85b1-2450-43fb-aabc-1687188af208	\N	doc-75f8446029de	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:53.178818+05:30	g:group-hr
8d6cd1dd-d534-4bac-8f31-b48ea5ee92be	\N	doc-75f8446029de	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:53.178818+05:30	r:hr
25c53600-54a8-4447-9709-bc14e41784b4	\N	doc-75f8446029de	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:53.178818+05:30	r:manager
63594c52-bf44-4131-891d-8c79997e6671	\N	doc-75f8446029de	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:53.178818+05:30	r:admin
2b90b7d6-db6b-42d3-9890-8b6629de30dd	\N	doc-75f8446029de	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:53.178818+05:30	r:employee
3980022a-513e-4e13-98ca-783d93ad6104	\N	doc-75f8446029de	\N	\N	\N	allow	read	source_sync	\N	2026-10-10 11:02:53.178818+05:30	p:project-001
\.


--
-- Data for Name: document_versions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.document_versions (id, tenant_id, document_id, version_no, source_revision, content_hash, storage_key, size_bytes, status, is_current, malware_status, pii_summary, approved_by, approved_at, effective_from, effective_to, indexed_at, created_at, version_number, checksum, revision_id, file_size) FROM stdin;
ver-3decb213	\N	doc-0718297b71e4	1	\N	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:05:17.792099+05:30	1	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	\N	438013
ver-77bab82c	\N	doc-0718297b71e4	2	\N	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:06:07.415405+05:30	2	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	\N	438013
ver-56f14fd8	\N	doc-de573a503f6d	1	\N	a290756586b5d023cbf769a2d6737e23eeec827f2737c7acac7ff81b4a1a8093	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:06:52.07165+05:30	1	a290756586b5d023cbf769a2d6737e23eeec827f2737c7acac7ff81b4a1a8093	\N	4068506
ver-af1db78e	\N	doc-03b90406eca2	1	\N	3de28924d2b74c67453f1cf6546ef7b09cf97d5d0e917495cb7d6492ce68de98	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:06:53.068293+05:30	1	3de28924d2b74c67453f1cf6546ef7b09cf97d5d0e917495cb7d6492ce68de98	\N	439646
ver-2870bb6f	\N	doc-0a51cdb40625	1	\N	9a57527c8542c1a0e5dd94b81b7c7ae24f02253404c9e5a9e3db2e4d9d2b7546	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:06:56.610555+05:30	1	9a57527c8542c1a0e5dd94b81b7c7ae24f02253404c9e5a9e3db2e4d9d2b7546	\N	457701
ver-d591d0f2	\N	doc-9a4395663625	1	\N	309d7e1bca8c1f8812763748140f92c568da2aae5dc1732405bb7efd99e0b271	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:07:00.543681+05:30	1	309d7e1bca8c1f8812763748140f92c568da2aae5dc1732405bb7efd99e0b271	\N	141440
ver-408e9912	\N	doc-becad9a82359	1	\N	eb7998fe4ee4a3418ee8c73b6e8d6ceaab3737b41bf7983fee156ed6c318d396	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:07:04.89316+05:30	1	eb7998fe4ee4a3418ee8c73b6e8d6ceaab3737b41bf7983fee156ed6c318d396	\N	120702
ver-3d7fd15f	\N	doc-b02ac5215dad	1	\N	90f6fcfb238effa1209a71d95ffbd0904f432f9c4abb931f19af30d91fb9112e	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:07:08.592374+05:30	1	90f6fcfb238effa1209a71d95ffbd0904f432f9c4abb931f19af30d91fb9112e	\N	139539
ver-871cf972	\N	doc-37cea547ae24	1	\N	f88a832aa151c8f4ca8e4e1f40ac50b92b70c1b6e3046345d687d62b8c84731a	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:07:12.99199+05:30	1	f88a832aa151c8f4ca8e4e1f40ac50b92b70c1b6e3046345d687d62b8c84731a	\N	131945
ver-76575f76	\N	doc-5e4f6cd7d179	1	\N	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:07:17.601498+05:30	1	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	\N	546541
ver-58e8bc5d	\N	doc-a453aa814971	1	\N	857bb4348dfbd151792a30879d93b38304d37f253c49b912d4c35e78a4cebb72	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:07:21.5653+05:30	1	857bb4348dfbd151792a30879d93b38304d37f253c49b912d4c35e78a4cebb72	\N	525936
ver-42aa2f8a	\N	doc-e9cdba142890	1	\N	73283d6096777f3696112b15fed9e175112aba9f7f958646d1adb955d5385ecb	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:07:27.491276+05:30	1	73283d6096777f3696112b15fed9e175112aba9f7f958646d1adb955d5385ecb	\N	135904
ver-4355ff10	\N	doc-bd628377481b	1	\N	4e89140e39b44a65b0c166223b92e3cd7fe4366cf43189f38c070c3284118453	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:07:31.842656+05:30	1	4e89140e39b44a65b0c166223b92e3cd7fe4366cf43189f38c070c3284118453	\N	749511
ver-e891bb59	\N	doc-eb33be1c8687	1	\N	0ef1f707e55db8dbdac1ffa693cd5a18bdde6919f6383adde4080d71474b0b2e	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:07:52.286531+05:30	1	0ef1f707e55db8dbdac1ffa693cd5a18bdde6919f6383adde4080d71474b0b2e	\N	136459
ver-25afcb85	\N	doc-8405e29cdc24	1	\N	6665de304da07f4a7dc702988092c54b930177bdc49ebc2e7f6658e1b740093b	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:07:56.541245+05:30	1	6665de304da07f4a7dc702988092c54b930177bdc49ebc2e7f6658e1b740093b	\N	132684
ver-7bae6ae1	\N	doc-43c0cbab0d45	1	\N	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:08:00.344448+05:30	1	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	\N	441074
ver-cfcc98e6	\N	doc-a2d6def96248	1	\N	bcabcfb1837cc830e0b6bc2ea85aa5e664203afcd2c4cdda0cf1df82450e159b	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:08:04.286892+05:30	1	bcabcfb1837cc830e0b6bc2ea85aa5e664203afcd2c4cdda0cf1df82450e159b	\N	443363
ver-3734fea0	\N	doc-fad3ce481e4b	1	\N	f8b1596b3bed8421fb1afc7232dc8a60ec876fce1b654fc18d94e2ac6d3ba78c	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-08 15:08:08.589588+05:30	1	f8b1596b3bed8421fb1afc7232dc8a60ec876fce1b654fc18d94e2ac6d3ba78c	\N	435724
ver-0a89f509	\N	doc-15c4f8adcd3f	1	\N	8ad202f3a48fc3b036ab2129764828d4d2a076b4170676d1a1b7070326a9cae1	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-09 04:22:36.743251+05:30	1	8ad202f3a48fc3b036ab2129764828d4d2a076b4170676d1a1b7070326a9cae1	\N	97
ver-15b2ecdc	\N	doc-50690e9459bb	1	\N	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:33:13.005325+05:30	1	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	\N	438013
ver-4601908c	\N	doc-6c4fc0bf754c	1	\N	3de28924d2b74c67453f1cf6546ef7b09cf97d5d0e917495cb7d6492ce68de98	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:33:52.569132+05:30	1	3de28924d2b74c67453f1cf6546ef7b09cf97d5d0e917495cb7d6492ce68de98	\N	439646
ver-83a8a46e	\N	doc-a8180f3bb43d	1	\N	9a57527c8542c1a0e5dd94b81b7c7ae24f02253404c9e5a9e3db2e4d9d2b7546	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:33:57.867786+05:30	1	9a57527c8542c1a0e5dd94b81b7c7ae24f02253404c9e5a9e3db2e4d9d2b7546	\N	457701
ver-d1b53198	\N	doc-24f027b6f4a7	1	\N	309d7e1bca8c1f8812763748140f92c568da2aae5dc1732405bb7efd99e0b271	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:34:04.193132+05:30	1	309d7e1bca8c1f8812763748140f92c568da2aae5dc1732405bb7efd99e0b271	\N	141440
ver-e85d905a	\N	doc-e8e98b8c83a3	1	\N	eb7998fe4ee4a3418ee8c73b6e8d6ceaab3737b41bf7983fee156ed6c318d396	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:34:10.132179+05:30	1	eb7998fe4ee4a3418ee8c73b6e8d6ceaab3737b41bf7983fee156ed6c318d396	\N	120702
ver-3e899ce9	\N	doc-75f8446029de	1	\N	90f6fcfb238effa1209a71d95ffbd0904f432f9c4abb931f19af30d91fb9112e	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:34:15.234135+05:30	1	90f6fcfb238effa1209a71d95ffbd0904f432f9c4abb931f19af30d91fb9112e	\N	139539
ver-897f5d21	\N	doc-f86ce675b533	1	\N	f88a832aa151c8f4ca8e4e1f40ac50b92b70c1b6e3046345d687d62b8c84731a	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:34:22.636427+05:30	1	f88a832aa151c8f4ca8e4e1f40ac50b92b70c1b6e3046345d687d62b8c84731a	\N	131945
ver-f21677ea	\N	doc-98940217eca3	1	\N	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:34:29.884513+05:30	1	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	\N	546541
ver-4a758112	\N	doc-ab5c26d1ac91	1	\N	857bb4348dfbd151792a30879d93b38304d37f253c49b912d4c35e78a4cebb72	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:34:35.99441+05:30	1	857bb4348dfbd151792a30879d93b38304d37f253c49b912d4c35e78a4cebb72	\N	525936
ver-1564e40d	\N	doc-3d054e40aba7	1	\N	73283d6096777f3696112b15fed9e175112aba9f7f958646d1adb955d5385ecb	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:34:44.281471+05:30	1	73283d6096777f3696112b15fed9e175112aba9f7f958646d1adb955d5385ecb	\N	135904
ver-1606e601	\N	doc-d6402dc16e20	1	\N	0ef1f707e55db8dbdac1ffa693cd5a18bdde6919f6383adde4080d71474b0b2e	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:34:50.338664+05:30	1	0ef1f707e55db8dbdac1ffa693cd5a18bdde6919f6383adde4080d71474b0b2e	\N	136459
ver-137ad6fc	\N	doc-cf0975b45d02	1	\N	6665de304da07f4a7dc702988092c54b930177bdc49ebc2e7f6658e1b740093b	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:34:57.874909+05:30	1	6665de304da07f4a7dc702988092c54b930177bdc49ebc2e7f6658e1b740093b	\N	132684
ver-6daa8829	\N	doc-4f328576121e	1	\N	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:35:05.297407+05:30	1	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	\N	441074
ver-181767bd	\N	doc-95f9bf76e643	1	\N	bcabcfb1837cc830e0b6bc2ea85aa5e664203afcd2c4cdda0cf1df82450e159b	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:35:12.841521+05:30	1	bcabcfb1837cc830e0b6bc2ea85aa5e664203afcd2c4cdda0cf1df82450e159b	\N	443363
ver-0e690a3b	\N	doc-f5e24b39a009	1	\N	f8b1596b3bed8421fb1afc7232dc8a60ec876fce1b654fc18d94e2ac6d3ba78c	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 10:35:23.373711+05:30	1	f8b1596b3bed8421fb1afc7232dc8a60ec876fce1b654fc18d94e2ac6d3ba78c	\N	435724
ver-8ca16edf	\N	doc-ff2f2247df35	1	\N	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:01:52.043119+05:30	1	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	130
ver-f4d346f5	\N	doc-ff2f2247df35	2	\N	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:01:53.566467+05:30	2	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	130
ver-558ec618	\N	doc-ff2f2247df35	3	\N	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:01:53.920816+05:30	3	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	130
ver-e28499e6	\N	doc-ff2f2247df35	4	\N	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:01:54.063283+05:30	4	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	130
ver-4f6493e3	\N	doc-ff2f2247df35	5	\N	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:01:54.139277+05:30	5	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	130
ver-a57fa3f0	\N	doc-ff2f2247df35	6	\N	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:02:01.761682+05:30	6	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	\N	130
ver-1cb0bac9	\N	doc-50690e9459bb	2	\N	e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:02:29.599047+05:30	2	e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855	\N	438013
ver-900162b3	\N	doc-50690e9459bb	3	\N	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:02:30.175956+05:30	3	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	\N	438013
ver-fc174a6d	\N	doc-98940217eca3	2	\N	e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:02:58.330577+05:30	2	e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855	\N	546541
ver-5ae9c1e0	\N	doc-98940217eca3	3	\N	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:02:58.844616+05:30	3	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	\N	546541
ver-e839e80c	\N	doc-98940217eca3	4	\N	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:02:59.426085+05:30	4	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	\N	546541
ver-c2f2c6b2	\N	doc-98940217eca3	5	\N	e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:03:00.556534+05:30	5	e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855	\N	546541
ver-804c165d	\N	doc-98940217eca3	6	\N	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:03:01.013815+05:30	6	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	\N	546541
ver-b51a7e3c	\N	doc-4f328576121e	2	\N	e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:03:24.151586+05:30	2	e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855	\N	441074
ver-e9e9af6c	\N	doc-4f328576121e	3	\N	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:03:24.305904+05:30	3	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	\N	441074
ver-0621e8a5	\N	doc-4f328576121e	4	\N	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	\N	\N	pending	f	pending	{}	\N	\N	\N	\N	\N	2026-10-10 11:03:24.972075+05:30	4	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	\N	441074
\.


--
-- Data for Name: documents; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.documents (id, name, source_hash, created_at, updated_at, tenant_id, project_id, source, source_uri, drive_file_id, mime_type, size_bytes, owner_email, web_view_link, revision_id, modified_time, checksum, status, summary, chunk_count, acl_version, access_roles, denied_users, folder_path, drive_link_id) FROM stdin;
doc-ff2f2247df35	folder_123	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	2026-10-10 11:01:52.026037	2026-10-10 16:38:05.909865	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1Da7uW8AFK094o2_7ctNX5nqwwOWNNJRy/view	1Da7uW8AFK094o2_7ctNX5nqwwOWNNJRy	application/pdf	130	\N	https://drive.google.com/file/d/1Da7uW8AFK094o2_7ctNX5nqwwOWNNJRy/view	\N	2026-10-10 11:01:52.026037	aee46ff6c54c03cfce00c0d72ceedea6ef558ff03148ec4513620bef35681a1f	ready	\N	1	5	["admin", "hr", "finance", "manager", "employee"]	[]	/test_folder_drive_link	1
doc-24f027b6f4a7	Employee_Data_Management_Procedure.pdf	309d7e1bca8c1f8812763748140f92c568da2aae5dc1732405bb7efd99e0b271	2026-10-10 10:34:04.191949	2026-10-10 16:32:41.54617	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/189yxYlCouoaWSoLxv5vs3-FhXAhXL-Q8/view	189yxYlCouoaWSoLxv5vs3-FhXAhXL-Q8	application/pdf	141440	\N	https://drive.google.com/file/d/189yxYlCouoaWSoLxv5vs3-FhXAhXL-Q8/view	\N	2026-10-10 10:34:04.191949	309d7e1bca8c1f8812763748140f92c568da2aae5dc1732405bb7efd99e0b271	ready	\N	5	11	["admin", "hr", "finance", "manager", "employee"]	[]	/	1
doc-50690e9459bb	Code_of_Employee_Conduct.pdf	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	2026-10-10 10:33:13.000819	2026-10-10 16:38:05.988314	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1KyQk8lKaAl_Oh8PmyYF4Rd29vxUSbJJT/view	1KyQk8lKaAl_Oh8PmyYF4Rd29vxUSbJJT	application/pdf	438013	\N	https://drive.google.com/file/d/1KyQk8lKaAl_Oh8PmyYF4Rd29vxUSbJJT/view	\N	2026-10-10 10:33:13.000819	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	ready	\N	4	8	["admin", "hr", "finance", "manager", "employee"]	[]	/test_folder_drive_link	1
doc-de573a503f6d	Cyber Rules.pdf	a290756586b5d023cbf769a2d6737e23eeec827f2737c7acac7ff81b4a1a8093	2026-10-08 15:06:52.066617	2026-10-10 16:04:44.805201	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Cyber Rules.pdf	\N	application/pdf	4068506	\N	\N	\N	2026-10-08 15:06:52.066617	a290756586b5d023cbf769a2d6737e23eeec827f2737c7acac7ff81b4a1a8093	ready	\N	1	26	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-3d054e40aba7	Performance_Review_Guidelines.pdf	73283d6096777f3696112b15fed9e175112aba9f7f958646d1adb955d5385ecb	2026-10-10 10:34:44.278966	2026-10-10 16:33:08.575414	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1WNc-JLkFnZOzBBFuLRhOeiB0daCQQ_UV/view	1WNc-JLkFnZOzBBFuLRhOeiB0daCQQ_UV	application/pdf	135904	\N	https://drive.google.com/file/d/1WNc-JLkFnZOzBBFuLRhOeiB0daCQQ_UV/view	\N	2026-10-10 10:34:44.278966	73283d6096777f3696112b15fed9e175112aba9f7f958646d1adb955d5385ecb	ready	\N	5	11	["admin", "hr", "finance", "manager", "employee"]	[]	/	1
doc-15c4f8adcd3f	sample_acme_policy.txt	8ad202f3a48fc3b036ab2129764828d4d2a076b4170676d1a1b7070326a9cae1	2026-10-09 04:22:36.735777	2026-10-09 09:53:11.856371	a3424830-6d45-4ad8-a43b-a5fdf70d691d	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\sample_acme_policy.txt	\N	application/pdf	97	\N	\N	\N	2026-10-09 04:22:36.735777	8ad202f3a48fc3b036ab2129764828d4d2a076b4170676d1a1b7070326a9cae1	ready	\N	1	2	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-e8e98b8c83a3	Employee_Grievance_Procedure.pdf	eb7998fe4ee4a3418ee8c73b6e8d6ceaab3737b41bf7983fee156ed6c318d396	2026-10-10 10:34:10.130666	2026-10-10 16:32:45.435165	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/11k5wgWcZZC4GmzzIyhjST453IhHLxTiu/view	11k5wgWcZZC4GmzzIyhjST453IhHLxTiu	application/pdf	120702	\N	https://drive.google.com/file/d/11k5wgWcZZC4GmzzIyhjST453IhHLxTiu/view	\N	2026-10-10 10:34:10.130666	eb7998fe4ee4a3418ee8c73b6e8d6ceaab3737b41bf7983fee156ed6c318d396	ready	\N	4	11	["admin", "hr", "finance", "manager", "employee"]	[]	/	1
doc-75f8446029de	Employee_Leave_Policy.pdf	90f6fcfb238effa1209a71d95ffbd0904f432f9c4abb931f19af30d91fb9112e	2026-10-10 10:34:15.231637	2026-10-10 16:32:49.484923	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1vXLv_aChMmaR-isryoinERd_f5OmmkfL/view	1vXLv_aChMmaR-isryoinERd_f5OmmkfL	application/pdf	139539	\N	https://drive.google.com/file/d/1vXLv_aChMmaR-isryoinERd_f5OmmkfL/view	\N	2026-10-10 10:34:15.231637	90f6fcfb238effa1209a71d95ffbd0904f432f9c4abb931f19af30d91fb9112e	ready	\N	6	11	["admin", "hr", "finance", "manager", "employee"]	[]	/	1
doc-ab5c26d1ac91	HR_Department_Annual_Report_FY2025-26.pdf	857bb4348dfbd151792a30879d93b38304d37f253c49b912d4c35e78a4cebb72	2026-10-10 10:34:35.992796	2026-10-10 16:33:08.529837	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1XKHiotyS5rc_3hd1th7ZahDBJo9p8IZ0/view	1XKHiotyS5rc_3hd1th7ZahDBJo9p8IZ0	application/pdf	525936	\N	https://drive.google.com/file/d/1XKHiotyS5rc_3hd1th7ZahDBJo9p8IZ0/view	\N	2026-10-10 10:34:35.992796	857bb4348dfbd151792a30879d93b38304d37f253c49b912d4c35e78a4cebb72	ready	\N	7	11	["admin", "hr", "finance", "manager", "employee"]	[]	/	1
doc-d6402dc16e20	Promotion_and_Career_Growth_Guidelines.pdf	0ef1f707e55db8dbdac1ffa693cd5a18bdde6919f6383adde4080d71474b0b2e	2026-10-10 10:34:50.336111	2026-10-10 16:33:12.124136	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1KYLgHQtklrBVeSC0NzGDUnKpyKMqgdYw/view	1KYLgHQtklrBVeSC0NzGDUnKpyKMqgdYw	application/pdf	136459	\N	https://drive.google.com/file/d/1KYLgHQtklrBVeSC0NzGDUnKpyKMqgdYw/view	\N	2026-10-10 10:34:50.336111	0ef1f707e55db8dbdac1ffa693cd5a18bdde6919f6383adde4080d71474b0b2e	ready	\N	5	12	["admin", "manager", "employee", "hr"]	["purvahead@apex.com"]	/	1
doc-a8180f3bb43d	Employee_Benefits_Handbook.pdf	9a57527c8542c1a0e5dd94b81b7c7ae24f02253404c9e5a9e3db2e4d9d2b7546	2026-10-10 10:33:57.864474	2026-10-10 16:32:37.812574	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1M1c3_CB5wRclWCTwL_tcqUlwxXB7emDj/view	1M1c3_CB5wRclWCTwL_tcqUlwxXB7emDj	application/pdf	457701	\N	https://drive.google.com/file/d/1M1c3_CB5wRclWCTwL_tcqUlwxXB7emDj/view	\N	2026-10-10 10:33:57.864474	9a57527c8542c1a0e5dd94b81b7c7ae24f02253404c9e5a9e3db2e4d9d2b7546	ready	\N	5	11	["admin", "hr", "finance", "manager", "employee"]	[]	/	1
doc-bd628377481b	Practical_3_24CS099.pdf	4e89140e39b44a65b0c166223b92e3cd7fe4366cf43189f38c070c3284118453	2026-10-08 15:07:31.837276	2026-10-10 16:04:45.692072	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Practical_3_24CS099.pdf	\N	application/pdf	749511	\N	\N	\N	2026-10-08 15:07:31.837276	4e89140e39b44a65b0c166223b92e3cd7fe4366cf43189f38c070c3284118453	ready	\N	21	26	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-6c4fc0bf754c	Employee_Attendance_Policy.pdf	3de28924d2b74c67453f1cf6546ef7b09cf97d5d0e917495cb7d6492ce68de98	2026-10-10 10:33:52.565997	2026-10-10 16:32:37.774604	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1B_eQ3Nz3mK-5Ex_RP0di246444--Rtw2/view	1B_eQ3Nz3mK-5Ex_RP0di246444--Rtw2	application/pdf	439646	\N	https://drive.google.com/file/d/1B_eQ3Nz3mK-5Ex_RP0di246444--Rtw2/view	\N	2026-10-10 10:33:52.565997	3de28924d2b74c67453f1cf6546ef7b09cf97d5d0e917495cb7d6492ce68de98	ready	\N	4	11	["admin", "hr", "finance", "manager", "employee"]	[]	/	1
doc-becad9a82359	Employee_Grievance_Procedure.pdf	eb7998fe4ee4a3418ee8c73b6e8d6ceaab3737b41bf7983fee156ed6c318d396	2026-10-08 15:07:04.889586	2026-10-10 16:04:46.296124	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Employee_Grievance_Procedure.pdf	\N	application/pdf	120702	\N	\N	\N	2026-10-08 15:07:04.889586	eb7998fe4ee4a3418ee8c73b6e8d6ceaab3737b41bf7983fee156ed6c318d396	ready	\N	4	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-a2d6def96248	Travel_and_Expense_Policy.pdf	bcabcfb1837cc830e0b6bc2ea85aa5e664203afcd2c4cdda0cf1df82450e159b	2026-10-08 15:08:04.28359	2026-10-10 16:04:46.410428	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Travel_and_Expense_Policy.pdf	\N	application/pdf	443363	\N	\N	\N	2026-10-08 15:08:04.28359	bcabcfb1837cc830e0b6bc2ea85aa5e664203afcd2c4cdda0cf1df82450e159b	ready	\N	5	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-9a4395663625	Employee_Data_Management_Procedure.pdf	309d7e1bca8c1f8812763748140f92c568da2aae5dc1732405bb7efd99e0b271	2026-10-08 15:07:00.536123	2026-10-10 16:04:46.500749	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Employee_Data_Management_Procedure.pdf	\N	application/pdf	141440	\N	\N	\N	2026-10-08 15:07:00.536123	309d7e1bca8c1f8812763748140f92c568da2aae5dc1732405bb7efd99e0b271	ready	\N	5	28	["admin", "hr", "finance", "employee"]	[]	/	\N
doc-37cea547ae24	Employee_Offboarding_Procedure.pdf	f88a832aa151c8f4ca8e4e1f40ac50b92b70c1b6e3046345d687d62b8c84731a	2026-10-08 15:07:12.988827	2026-10-10 16:04:46.627315	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Employee_Offboarding_Procedure.pdf	\N	application/pdf	131945	\N	\N	\N	2026-10-08 15:07:12.988827	f88a832aa151c8f4ca8e4e1f40ac50b92b70c1b6e3046345d687d62b8c84731a	ready	\N	5	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-03b90406eca2	Employee_Attendance_Policy.pdf	3de28924d2b74c67453f1cf6546ef7b09cf97d5d0e917495cb7d6492ce68de98	2026-10-08 15:06:53.063696	2026-10-10 16:04:46.730237	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Employee_Attendance_Policy.pdf	\N	application/pdf	439646	\N	\N	\N	2026-10-08 15:06:53.063696	3de28924d2b74c67453f1cf6546ef7b09cf97d5d0e917495cb7d6492ce68de98	ready	\N	4	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-5e4f6cd7d179	Employee_Onboarding_Procedure.pdf	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	2026-10-08 15:07:17.596203	2026-10-10 16:04:46.829111	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Employee_Onboarding_Procedure.pdf	\N	application/pdf	546541	\N	\N	\N	2026-10-08 15:07:17.595567	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	ready	\N	5	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-43c0cbab0d45	Training_and_Development_Policy.pdf	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	2026-10-08 15:08:00.342745	2026-10-10 16:04:46.931978	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Training_and_Development_Policy.pdf	\N	application/pdf	441074	\N	\N	\N	2026-10-08 15:08:00.342745	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	ready	\N	5	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-eb33be1c8687	Promotion_and_Career_Growth_Guidelines.pdf	0ef1f707e55db8dbdac1ffa693cd5a18bdde6919f6383adde4080d71474b0b2e	2026-10-08 15:07:52.281797	2026-10-10 16:04:47.062769	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Promotion_and_Career_Growth_Guidelines.pdf	\N	application/pdf	136459	\N	\N	\N	2026-10-08 15:07:52.281797	0ef1f707e55db8dbdac1ffa693cd5a18bdde6919f6383adde4080d71474b0b2e	ready	\N	5	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-0718297b71e4	Code_of_Employee_Conduct.pdf	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	2026-10-08 15:05:17.782523	2026-10-10 16:04:47.146844	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Code_of_Employee_Conduct.pdf	\N	application/pdf	438013	\N	\N	\N	2026-10-08 15:05:17.782523	734fa74a018210ae1b1947aa3eea4af5b2be5a2ceab3ed159c23d1a96c4d4a6c	ready	\N	4	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-0a51cdb40625	Employee_Benefits_Handbook.pdf	9a57527c8542c1a0e5dd94b81b7c7ae24f02253404c9e5a9e3db2e4d9d2b7546	2026-10-08 15:06:56.606348	2026-10-10 16:04:47.247	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Employee_Benefits_Handbook.pdf	\N	application/pdf	457701	\N	\N	\N	2026-10-08 15:06:56.606348	9a57527c8542c1a0e5dd94b81b7c7ae24f02253404c9e5a9e3db2e4d9d2b7546	ready	\N	5	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-fad3ce481e4b	Work_From_Home_Policy.pdf	f8b1596b3bed8421fb1afc7232dc8a60ec876fce1b654fc18d94e2ac6d3ba78c	2026-10-08 15:08:08.58658	2026-10-10 16:04:47.336166	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Work_From_Home_Policy.pdf	\N	application/pdf	435724	\N	\N	\N	2026-10-08 15:08:08.58658	f8b1596b3bed8421fb1afc7232dc8a60ec876fce1b654fc18d94e2ac6d3ba78c	ready	\N	4	28	["admin", "hr", "manager"]	[]	/	\N
doc-8405e29cdc24	Remote_Work_Security_Guidelines.pdf	6665de304da07f4a7dc702988092c54b930177bdc49ebc2e7f6658e1b740093b	2026-10-08 15:07:56.536754	2026-10-10 16:04:47.432381	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Remote_Work_Security_Guidelines.pdf	\N	application/pdf	132684	\N	\N	\N	2026-10-08 15:07:56.536754	6665de304da07f4a7dc702988092c54b930177bdc49ebc2e7f6658e1b740093b	ready	\N	5	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-b02ac5215dad	Employee_Leave_Policy.pdf	90f6fcfb238effa1209a71d95ffbd0904f432f9c4abb931f19af30d91fb9112e	2026-10-08 15:07:08.590031	2026-10-10 16:04:47.543557	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Employee_Leave_Policy.pdf	\N	application/pdf	139539	\N	\N	\N	2026-10-08 15:07:08.590031	90f6fcfb238effa1209a71d95ffbd0904f432f9c4abb931f19af30d91fb9112e	ready	\N	6	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-e9cdba142890	Performance_Review_Guidelines.pdf	73283d6096777f3696112b15fed9e175112aba9f7f958646d1adb955d5385ecb	2026-10-08 15:07:27.485826	2026-10-10 16:04:47.631625	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\Performance_Review_Guidelines.pdf	\N	application/pdf	135904	\N	\N	\N	2026-10-08 15:07:27.485826	73283d6096777f3696112b15fed9e175112aba9f7f958646d1adb955d5385ecb	ready	\N	5	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-a453aa814971	HR_Department_Annual_Report_FY2025-26.pdf	857bb4348dfbd151792a30879d93b38304d37f253c49b912d4c35e78a4cebb72	2026-10-08 15:07:21.560942	2026-10-10 16:04:47.733492	tenant-001	project-001	local	D:\\sgp\\24CS26031_EnterpriseDataRetrieval\\backend\\data\\HR_Department_Annual_Report_FY2025-26.pdf	\N	application/pdf	525936	\N	\N	\N	2026-10-08 15:07:21.560942	857bb4348dfbd151792a30879d93b38304d37f253c49b912d4c35e78a4cebb72	ready	\N	7	27	["admin", "hr", "finance", "manager", "employee"]	[]	/	\N
doc-f86ce675b533	Employee_Offboarding_Procedure.pdf	f88a832aa151c8f4ca8e4e1f40ac50b92b70c1b6e3046345d687d62b8c84731a	2026-10-10 10:34:22.634533	2026-10-10 16:32:53.240816	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/18SN5X3tHYFx-YwVYnafCReYsnB1mMZXY/view	18SN5X3tHYFx-YwVYnafCReYsnB1mMZXY	application/pdf	131945	\N	https://drive.google.com/file/d/18SN5X3tHYFx-YwVYnafCReYsnB1mMZXY/view	\N	2026-10-10 10:34:22.634533	f88a832aa151c8f4ca8e4e1f40ac50b92b70c1b6e3046345d687d62b8c84731a	ready	\N	5	11	["admin", "hr", "finance", "manager", "employee"]	[]	/	1
doc-98940217eca3	Employee_Onboarding_Procedure.pdf	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	2026-10-10 10:34:29.880949	2026-10-10 16:38:06.152837	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1dVroX6pwdBdI2cfXCdm4Ksa3k_WcM-LD/view	1dVroX6pwdBdI2cfXCdm4Ksa3k_WcM-LD	application/pdf	546541	\N	https://drive.google.com/file/d/1dVroX6pwdBdI2cfXCdm4Ksa3k_WcM-LD/view	\N	2026-10-10 10:34:29.880949	50485f7a6b4b9587f00ce621d60b9d1b61b9ad78cfe2f196129512e172ab31a0	ready	\N	5	11	["admin", "hr", "finance", "manager", "employee"]	[]	/test_folder_drive_link	1
doc-f5e24b39a009	Work_From_Home_Policy.pdf	f8b1596b3bed8421fb1afc7232dc8a60ec876fce1b654fc18d94e2ac6d3ba78c	2026-10-10 10:35:23.370714	2026-10-10 16:53:42.797706	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1mQD3D3fzhOAz0e4G7wdCWajpLqQKD-ME/view	1mQD3D3fzhOAz0e4G7wdCWajpLqQKD-ME	application/pdf	435724	\N	https://drive.google.com/file/d/1mQD3D3fzhOAz0e4G7wdCWajpLqQKD-ME/view	\N	2026-10-10 10:35:23.370714	f8b1596b3bed8421fb1afc7232dc8a60ec876fce1b654fc18d94e2ac6d3ba78c	ready	\N	4	12	["admin", "finance", "manager", "employee", "hr"]	["purvahead@apex.com"]	/	1
doc-95f9bf76e643	Travel_and_Expense_Policy.pdf	bcabcfb1837cc830e0b6bc2ea85aa5e664203afcd2c4cdda0cf1df82450e159b	2026-10-10 10:35:12.835973	2026-10-10 16:33:32.088983	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/17oxYWTLLqpTRY84NxB57LMhDfnN2zTb0/view	17oxYWTLLqpTRY84NxB57LMhDfnN2zTb0	application/pdf	443363	\N	https://drive.google.com/file/d/17oxYWTLLqpTRY84NxB57LMhDfnN2zTb0/view	\N	2026-10-10 10:35:12.835973	bcabcfb1837cc830e0b6bc2ea85aa5e664203afcd2c4cdda0cf1df82450e159b	ready	\N	5	11	["admin", "hr", "finance", "manager", "employee"]	[]	/	1
doc-cf0975b45d02	Remote_Work_Security_Guidelines.pdf	6665de304da07f4a7dc702988092c54b930177bdc49ebc2e7f6658e1b740093b	2026-10-10 10:34:57.8727	2026-10-10 16:33:16.029042	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1PUCkhw5SS0UD5y6FoXOo8gnDR5aa7Dzq/view	1PUCkhw5SS0UD5y6FoXOo8gnDR5aa7Dzq	application/pdf	132684	\N	https://drive.google.com/file/d/1PUCkhw5SS0UD5y6FoXOo8gnDR5aa7Dzq/view	\N	2026-10-10 10:34:57.8727	6665de304da07f4a7dc702988092c54b930177bdc49ebc2e7f6658e1b740093b	ready	\N	5	11	["admin", "hr", "finance", "manager", "employee"]	[]	/	1
doc-4f328576121e	Training_and_Development_Policy.pdf	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	2026-10-10 10:35:05.294165	2026-10-10 16:38:06.085308	df672f52-b432-45f1-b1a6-4b4b78e23065	project-001	google_drive	https://drive.google.com/file/d/1HWuvh_Z89R2SdXEw_-TPMpxfe4m8ZeOb/view	1HWuvh_Z89R2SdXEw_-TPMpxfe4m8ZeOb	application/pdf	441074	\N	https://drive.google.com/file/d/1HWuvh_Z89R2SdXEw_-TPMpxfe4m8ZeOb/view	\N	2026-10-10 10:35:05.294165	e062a7fa08959b4bfc688ecb882d39b3d99d6f44d8bc146982a576c23eb090b8	ready	\N	5	12	["admin", "hr", "finance", "manager", "employee"]	[]	/test_folder_drive_link	1
\.


--
-- Data for Name: enterprise_admins; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.enterprise_admins (id, enterprise_name, admin_email, temp_password, user_id, tenant_id, is_active, created_at, updated_at) FROM stdin;
3	cmp3	cmp3@example.com	EntPass#XyetbA!	e4130151-2b46-40e5-b604-ed235045a782	69bb5e9f-858a-4cdc-a6f4-e05b1a80494b	t	2026-10-09 04:29:28.521679+05:30	2026-10-10 17:11:32.370464+05:30
1	Acme Corporation	admin@acmecorp.com	Password123!	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	a3424830-6d45-4ad8-a43b-a5fdf70d691d	t	2026-10-08 16:08:10.301728+05:30	2026-10-10 17:11:32.370464+05:30
2	Apex Technologies	admin@apex.com	Password1234!	a333efea-a6ac-461f-9639-0a06153c37da	df672f52-b432-45f1-b1a6-4b4b78e23065	t	2026-10-08 17:03:52.683196+05:30	2026-10-10 17:11:32.370464+05:30
\.


--
-- Data for Name: enterprise_drive_links; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.enterprise_drive_links (id, tenant_id, name, drive_url, drive_id, is_folder, password_hash, status, doc_count, created_by_id, created_at, updated_at) FROM stdin;
1	df672f52-b432-45f1-b1a6-4b4b78e23065	test_folder_drive_link	https://drive.google.com/drive/folders/1I9x9ihja3-FIVT7urWgZsTKWWvU4kjE7?usp=drive_link	1I9x9ihja3-FIVT7urWgZsTKWWvU4kjE7	t	\N	synced	0	a333efea-a6ac-461f-9639-0a06153c37da	2026-10-10 10:12:08.891351+05:30	2026-10-10 11:03:35.874644+05:30
\.


--
-- Data for Name: external_identities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.external_identities (id, tenant_id, user_id, source_type, external_id, external_email) FROM stdin;
\.


--
-- Data for Name: feedback; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.feedback (id, query_log_id, user_id, is_positive, comment, created_at) FROM stdin;
1	4	61bdc8eb-3dd9-4383-9c10-91bb052e7207	f	\N	2026-10-07 19:13:19.010099
2	4	61bdc8eb-3dd9-4383-9c10-91bb052e7207	f	\N	2026-10-07 19:13:21.011553
3	4	61bdc8eb-3dd9-4383-9c10-91bb052e7207	t	\N	2026-10-07 19:13:24.233333
4	7	61bdc8eb-3dd9-4383-9c10-91bb052e7207	t	\N	2026-10-08 20:20:34.990977
\.


--
-- Data for Name: group_members; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.group_members (id, tenant_id, group_id, member_user_id, member_group_id, created_at, user_id) FROM stdin;
\.


--
-- Data for Name: groups; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.groups (id, tenant_id, name, origin, source_connection_id, external_ref, created_at, key, description) FROM stdin;
\.


--
-- Data for Name: identity_providers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.identity_providers (id, tenant_id, type, issuer, client_id, secret_ref, claim_mappings, jit_provisioning, scim_enabled, enabled, created_at) FROM stdin;
\.


--
-- Data for Name: ingestion_jobs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ingestion_jobs (id, tenant_id, document_version_id, stage, status, attempts, error, started_at, finished_at) FROM stdin;
e1bf3d86-30ff-441f-a526-de8dbac4b989	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	113b1c4a-ea37-4b72-828b-1ee74ff2addf	done	succeeded	1	\N	2026-10-07 11:34:28.883851+05:30	2026-10-07 11:34:28.883851+05:30
81f86ef0-07bf-4e69-8125-dcc47659edd4	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	327e9a11-8c85-4791-9ae7-ce50ca864fd5	done	succeeded	1	\N	2026-10-07 11:34:33.821513+05:30	2026-10-07 11:34:33.821513+05:30
e129f6fe-e1d4-4213-a37e-417e28280bab	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	4525243b-eefa-4a41-b7b1-a3487256bcbe	done	succeeded	1	\N	2026-10-07 11:34:34.272371+05:30	2026-10-07 11:34:34.272371+05:30
e7333cf7-7037-4c8e-a32d-f148cc7dd34e	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	7ebd9789-507c-45ca-87c2-3f79267f569f	done	succeeded	1	\N	2026-10-07 11:34:34.865246+05:30	2026-10-07 11:34:34.865246+05:30
b1c25d0c-1955-4d66-ac32-df3c6b06deff	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	3a0d6a5a-e1a4-4388-8d76-0611ae7d5d7b	done	succeeded	1	\N	2026-10-07 11:34:35.827699+05:30	2026-10-07 11:34:35.827699+05:30
93620576-7a6e-4fd5-bb93-aceddef040cd	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	61a3a63f-87ea-4897-afb0-9cc665849178	done	succeeded	1	\N	2026-10-07 11:34:36.277459+05:30	2026-10-07 11:34:36.277459+05:30
ec934945-7912-4282-bd3a-9b21bbf6eb4d	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	2487487b-dcd4-417b-ab0a-4c20cce4f29d	done	succeeded	1	\N	2026-10-07 11:34:36.990999+05:30	2026-10-07 11:34:36.990999+05:30
2ab24837-65c9-4e2c-8905-fceb600cda4f	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	c1889158-7fcb-428b-83d3-66f9a56daee5	done	succeeded	1	\N	2026-10-07 11:34:37.663184+05:30	2026-10-07 11:34:37.663184+05:30
734e4f06-31ce-49f5-a82a-b3e9b77c4e7a	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	83972e37-0329-4877-9b5f-796dd5b625ad	done	succeeded	1	\N	2026-10-07 11:34:37.956374+05:30	2026-10-07 11:34:37.956374+05:30
17502b42-e5d9-4c65-bfc3-a07bdd50fa03	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	4f5710f5-90e2-4ad4-8fb6-2ec149d3c258	done	succeeded	1	\N	2026-10-07 11:34:38.777414+05:30	2026-10-07 11:34:38.777414+05:30
d19e7a71-a1ac-4a79-96e9-14e582b75df2	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	9db68ebc-177b-4c5d-b8d4-aa7d6786b536	done	succeeded	1	\N	2026-10-07 11:34:39.407995+05:30	2026-10-07 11:34:39.407995+05:30
c9812eba-b5a8-4e06-8843-996d55b1eb40	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	d4bb6828-1fb4-4010-b2b0-d5a721ebdaa5	done	succeeded	1	\N	2026-10-07 11:34:40.782881+05:30	2026-10-07 11:34:40.782881+05:30
91854067-e897-4758-8978-da407637fe93	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	12842062-8e7b-4c0d-a8c7-bd5b8fc0175b	done	succeeded	1	\N	2026-10-07 11:34:41.760075+05:30	2026-10-07 11:34:41.760075+05:30
f6cf8845-329f-45af-9d7a-d55057c74133	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	c9eb8ebe-1efb-4baa-8e28-75ff33d328ac	done	succeeded	1	\N	2026-10-07 11:34:42.574159+05:30	2026-10-07 11:34:42.574159+05:30
2dfeecd8-c5aa-4f2f-a12a-e10bfa55916e	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	29a3f2f1-3ab8-4f68-971b-304f37369f62	done	succeeded	1	\N	2026-10-07 11:34:43.553363+05:30	2026-10-07 11:34:43.553363+05:30
\.


--
-- Data for Name: message_citations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.message_citations (id, tenant_id, message_id, chunk_id, document_id, version_id, rank, quote_start, quote_end, was_current_at_answer_time) FROM stdin;
\.


--
-- Data for Name: message_feedback; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.message_feedback (id, tenant_id, message_id, user_id, rating, category, comment, status, created_at) FROM stdin;
2871d5d7-e1ed-4f8e-b713-afc9f65dd2d1	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	433959d3-a28c-4eda-8166-99df9fc2c490	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	1	other	Very accurate answer	new	2026-10-06 16:28:57.010314+05:30
b82cc6a4-a3e8-4ec8-a5ad-944cf359b059	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	3082643f-2d40-4559-af03-c20fd851f19d	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	1	other	Very accurate answer	new	2026-10-06 16:30:15.372548+05:30
0784128a-8ec1-4c7c-a1da-16deecd0830d	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	ea521b48-f613-4bfe-828f-371c1594ea26	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	1	other	Very accurate answer	new	2026-10-06 16:31:21.485037+05:30
bd378307-c494-4ac0-bb04-9747d1c901ca	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0ae65968-99c8-4376-a7c1-0b67cea2dc99	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	1	other	Very accurate answer	new	2026-10-06 22:02:03.227265+05:30
7c576b38-3798-4bf2-8d3e-60dccb434adb	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	673f31f1-0f37-42fe-bcf8-5585cc32febb	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	-1	other	Negative / Incomplete response	new	2026-10-06 22:12:29.620024+05:30
\.


--
-- Data for Name: messages; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.messages (id, tenant_id, conversation_id, role, content, answer_type, confidence, model, prompt_tokens, completion_tokens, created_at) FROM stdin;
1a015a79-e362-42e7-acbb-3800eced1d0d	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	b451ca90-b22a-44b0-b2ae-4944a8494f54	user	What is the annual leave and PTO rollover policy?	answered	\N	\N	\N	\N	2026-10-06 16:28:56.502212+05:30
b4ae07c1-bc9d-4d67-a97f-931db0e272b1	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	b451ca90-b22a-44b0-b2ae-4944a8494f54	assistant	# Annual Leave and Paid Time Off (PTO) Guidelines ## 1. PTO Accrual Full-time employees accrue 20 days of paid vacation per calendar year (1.67 days per month). Employees with over 5 years of tenure accrue 25 days annually. ## 2. Sick Leave Employees receive 10 paid sick days per year, allotted on January 1st. Sick leave does not carry over across calendar years and is not paid out upon separation. ## 3. Rollover Policy A maximum of 5 unused\nis not paid out upon separation. ## 3. Rollover Policy A maximum of 5 unused vacation days may be rolled over into the subsequent calendar year. Rolled-over days must be utilized by March 31st of the new year, after which they expire. ## 4. Parental and Bereavement Leave Primary caregivers receive 16 weeks of fully paid parental leave. Secondary caregivers receive 8 weeks of fully paid parental leave. Bereavement leave provides up to 5\n8 weeks of fully paid parental leave. Bereavement leave provides up to 5 consecutive paid days for immediate family members.	answered	\N	gemini	\N	\N	2026-10-06 16:28:56.503212+05:30
01ba1286-a14b-40a7-b57c-959cd29cf8b5	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	676c64ca-bc65-4b8e-80c8-ea968701569d	user	What are the executive salary bands and bonus multipliers?	answered	\N	\N	\N	\N	2026-10-06 16:28:56.652968+05:30
3fd7ae90-f850-437c-b584-7862e611afdb	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	676c64ca-bc65-4b8e-80c8-ea968701569d	assistant	Based on Workplace Safety And Emergency (Page 1): adjustable standing desks, ergonomic chairs, and monitor arms upon request to Facilities....	answered	\N	gemini	\N	\N	2026-10-06 16:28:56.652968+05:30
8dda667c-3cc3-43a1-806d-a3d1b7d293a7	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	8c82c91e-8c91-43f2-ba67-0310bff1c782	user	What are the executive salary bands and bonus multipliers?	answered	\N	\N	\N	\N	2026-10-06 16:28:56.783326+05:30
830f19b1-58b9-4b87-a16b-49769244a0a1	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	8c82c91e-8c91-43f2-ba67-0310bff1c782	assistant	HR Confidential: Executive Salary Bands and Equity Matrix --- Page 1 --- HR CONFIDENTIAL - Compensation Structure 2026. Section 1: Level Grades and Base Salary Ranges. L3 Associate: $85,000 - $115,000. L4 Mid-Level: $115,000 - $155,000. L5 Senior: $155,000 - $205,000. L6 Staff / Principal: $205,000 - $265,000. L7 Director: $265,000 - $340,000. L8 Vice President: $340,000 - $450,000 base. --- Page 2 --- Section 2: Annual Incentive Bonus Target\n- $450,000 base. --- Page 2 --- Section 2: Annual Incentive Bonus Target Percentages. L3-L4 target bonus: 10% of base salary. L5 target bonus: 15% of base salary. L6 target bonus: 20% of base salary. L7-L8 executive bonus: 30% to 40% based on company ARR growth and EBITDA targets. --- Page 3 --- Section 3: Equity Grant Guidelines and RSU Vesting. Initial equity grants follow a 4-year vesting schedule with a 1-year cliff (25% at 12 months,\nStrategic Retention Bonus Pools To prevent poaching of top technical architects and business leaders, the Executive Committee authorizes retention bonus packages: Retention Grants: Cash bonuses paid over a 2-year retention window with 50% milestone at month 12 and 50% at month 24. Accelerated Vesting: In double-trigger change-of-control events, designated key personnel receive 100% immediate acceleration of unvested equity. 3. Key-Person Life	answered	\N	gemini	\N	\N	2026-10-06 16:28:56.783326+05:30
e330617c-036f-4e5f-89c8-fc23e77670e7	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0bff4c31-6c3d-47b1-8870-2c2a8745c492	user	Write Java code for binary search algorithm.	answered	\N	\N	\N	\N	2026-10-06 16:28:56.888747+05:30
ed02df91-59e5-49f9-bea2-6fc88d02d5e8	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0bff4c31-6c3d-47b1-8870-2c2a8745c492	assistant	I do not have enough information in the accessible documents to answer this question.	refused	\N	gemini	\N	\N	2026-10-06 16:28:56.888747+05:30
142844cd-34f2-4e4c-b57c-b6056d116088	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f5679689-b442-4c11-8fbd-1f86e531a201	user	Where are fire emergency assembly points?	answered	\N	\N	\N	\N	2026-10-06 16:28:56.98427+05:30
433959d3-a28c-4eda-8166-99df9fc2c490	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f5679689-b442-4c11-8fbd-1f86e531a201	assistant	Workplace Safety and Emergency Procedures 1. Emergency Evacuation In the event of a fire alarm or emergency evacuation: Immediately stop work and proceed calmly to the nearest designated emergency exit stairwell. Do not use elevators during a fire evacuation. Assemble at the Designated Assembly Point located in the North Parking Plaza and check in with your Floor Safety Warden. 2. Medical Emergencies and First Aid First aid kits and Automated	answered	\N	gemini	\N	\N	2026-10-06 16:28:56.98427+05:30
47dafd3a-58cf-4911-8c4b-e33381557fe3	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	6ce957c3-414e-45f8-8131-68fd02755d9a	user	What is the annual leave and PTO rollover policy?	answered	\N	\N	\N	\N	2026-10-06 16:30:14.894192+05:30
65a76d7e-bfd0-4a40-95c9-ded6e3048493	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	6ce957c3-414e-45f8-8131-68fd02755d9a	assistant	# Annual Leave and Paid Time Off (PTO) Guidelines ## 1. PTO Accrual Full-time employees accrue 20 days of paid vacation per calendar year (1.67 days per month). Employees with over 5 years of tenure accrue 25 days annually. ## 2. Sick Leave Employees receive 10 paid sick days per year, allotted on January 1st. Sick leave does not carry over across calendar years and is not paid out upon separation. ## 3. Rollover Policy A maximum of 5 unused\nis not paid out upon separation. ## 3. Rollover Policy A maximum of 5 unused vacation days may be rolled over into the subsequent calendar year. Rolled-over days must be utilized by March 31st of the new year, after which they expire. ## 4. Parental and Bereavement Leave Primary caregivers receive 16 weeks of fully paid parental leave. Secondary caregivers receive 8 weeks of fully paid parental leave. Bereavement leave provides up to 5\n8 weeks of fully paid parental leave. Bereavement leave provides up to 5 consecutive paid days for immediate family members.	answered	\N	gemini	\N	\N	2026-10-06 16:30:14.894192+05:30
622df8b6-6fe1-4a4a-b5c4-b716f90436aa	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	1c4a0119-c33e-4e1f-bd27-0377827f2357	user	What are the executive salary bands and bonus multipliers?	answered	\N	\N	\N	\N	2026-10-06 16:30:15.027835+05:30
021f7bcc-89a9-4a71-8965-3040a42a94e4	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	1c4a0119-c33e-4e1f-bd27-0377827f2357	assistant	I do not have enough information in the accessible documents to answer this question.	refused	\N	gemini	\N	\N	2026-10-06 16:30:15.028838+05:30
92134d8d-e6ad-4cdf-9143-b4c6d561149d	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	671f00d0-fc8a-49e7-ae63-2e265fd34521	user	What are the executive salary bands and bonus multipliers?	answered	\N	\N	\N	\N	2026-10-06 16:30:15.151191+05:30
c057209a-f919-4e7f-8cb0-c83e1ab75c78	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	671f00d0-fc8a-49e7-ae63-2e265fd34521	assistant	HR Confidential: Executive Salary Bands and Equity Matrix --- Page 1 --- HR CONFIDENTIAL - Compensation Structure 2026. Section 1: Level Grades and Base Salary Ranges. L3 Associate: $85,000 - $115,000. L4 Mid-Level: $115,000 - $155,000. L5 Senior: $155,000 - $205,000. L6 Staff / Principal: $205,000 - $265,000. L7 Director: $265,000 - $340,000. L8 Vice President: $340,000 - $450,000 base. --- Page 2 --- Section 2: Annual Incentive Bonus Target\n- $450,000 base. --- Page 2 --- Section 2: Annual Incentive Bonus Target Percentages. L3-L4 target bonus: 10% of base salary. L5 target bonus: 15% of base salary. L6 target bonus: 20% of base salary. L7-L8 executive bonus: 30% to 40% based on company ARR growth and EBITDA targets. --- Page 3 --- Section 3: Equity Grant Guidelines and RSU Vesting. Initial equity grants follow a 4-year vesting schedule with a 1-year cliff (25% at 12 months,\nStrategic Retention Bonus Pools To prevent poaching of top technical architects and business leaders, the Executive Committee authorizes retention bonus packages: Retention Grants: Cash bonuses paid over a 2-year retention window with 50% milestone at month 12 and 50% at month 24. Accelerated Vesting: In double-trigger change-of-control events, designated key personnel receive 100% immediate acceleration of unvested equity. 3. Key-Person Life	answered	\N	gemini	\N	\N	2026-10-06 16:30:15.152191+05:30
90a30e0a-1cd3-40a1-8502-64406347528a	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	c3bb329b-8cf3-47ba-a9b5-33317446aa00	user	Write Java code for binary search algorithm.	answered	\N	\N	\N	\N	2026-10-06 16:30:15.258842+05:30
004216a2-7aad-4344-bbf3-7e87fab50f23	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	c3bb329b-8cf3-47ba-a9b5-33317446aa00	assistant	I do not have enough information in the accessible documents to answer this question.	refused	\N	gemini	\N	\N	2026-10-06 16:30:15.259844+05:30
5a6e1d45-362e-44fd-997d-94f2fde909ec	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f9821b76-8662-4886-b18a-e0ce590fa0b6	user	Where are fire emergency assembly points?	answered	\N	\N	\N	\N	2026-10-06 16:30:15.352031+05:30
3082643f-2d40-4559-af03-c20fd851f19d	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f9821b76-8662-4886-b18a-e0ce590fa0b6	assistant	Workplace Safety and Emergency Procedures 1. Emergency Evacuation In the event of a fire alarm or emergency evacuation: Immediately stop work and proceed calmly to the nearest designated emergency exit stairwell. Do not use elevators during a fire evacuation. Assemble at the Designated Assembly Point located in the North Parking Plaza and check in with your Floor Safety Warden. 2. Medical Emergencies and First Aid First aid kits and Automated	answered	\N	gemini	\N	\N	2026-10-06 16:30:15.352031+05:30
42292c80-4d33-4af8-b211-d89a51829082	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	45b96c4d-eaa6-42b1-bee0-2cc96087f9b1	user	What is the annual leave and PTO rollover policy?	answered	\N	\N	\N	\N	2026-10-06 16:31:20.997594+05:30
083055e1-a8cf-4968-b12c-65ec17d54978	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	45b96c4d-eaa6-42b1-bee0-2cc96087f9b1	assistant	# Annual Leave and Paid Time Off (PTO) Guidelines ## 1. PTO Accrual Full-time employees accrue 20 days of paid vacation per calendar year (1.67 days per month). Employees with over 5 years of tenure accrue 25 days annually. ## 2. Sick Leave Employees receive 10 paid sick days per year, allotted on January 1st. Sick leave does not carry over across calendar years and is not paid out upon separation. ## 3. Rollover Policy A maximum of 5 unused\nis not paid out upon separation. ## 3. Rollover Policy A maximum of 5 unused vacation days may be rolled over into the subsequent calendar year. Rolled-over days must be utilized by March 31st of the new year, after which they expire. ## 4. Parental and Bereavement Leave Primary caregivers receive 16 weeks of fully paid parental leave. Secondary caregivers receive 8 weeks of fully paid parental leave. Bereavement leave provides up to 5\n8 weeks of fully paid parental leave. Bereavement leave provides up to 5 consecutive paid days for immediate family members.	answered	\N	gemini	\N	\N	2026-10-06 16:31:20.998594+05:30
ca8691f5-eb41-460a-bc30-b5de903a8de4	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	39d63abe-0acb-4745-ae96-bf3c02ca0e05	user	What are the executive salary bands and bonus multipliers?	answered	\N	\N	\N	\N	2026-10-06 16:31:21.13014+05:30
f1e51193-0970-4707-98a4-0de55eebb955	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	39d63abe-0acb-4745-ae96-bf3c02ca0e05	assistant	I do not have enough information in the accessible documents to answer this question.	refused	\N	gemini	\N	\N	2026-10-06 16:31:21.13014+05:30
377bd1d4-4ad4-4862-b46c-322d5bc224e6	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	3197608e-547f-4645-8148-57b832df6936	user	What are the executive salary bands and bonus multipliers?	answered	\N	\N	\N	\N	2026-10-06 16:31:21.26536+05:30
6f76ae36-754f-4586-addf-0675eaa5c00f	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	3197608e-547f-4645-8148-57b832df6936	assistant	HR Confidential: Executive Salary Bands and Equity Matrix --- Page 1 --- HR CONFIDENTIAL - Compensation Structure 2026. Section 1: Level Grades and Base Salary Ranges. L3 Associate: $85,000 - $115,000. L4 Mid-Level: $115,000 - $155,000. L5 Senior: $155,000 - $205,000. L6 Staff / Principal: $205,000 - $265,000. L7 Director: $265,000 - $340,000. L8 Vice President: $340,000 - $450,000 base. --- Page 2 --- Section 2: Annual Incentive Bonus Target\n- $450,000 base. --- Page 2 --- Section 2: Annual Incentive Bonus Target Percentages. L3-L4 target bonus: 10% of base salary. L5 target bonus: 15% of base salary. L6 target bonus: 20% of base salary. L7-L8 executive bonus: 30% to 40% based on company ARR growth and EBITDA targets. --- Page 3 --- Section 3: Equity Grant Guidelines and RSU Vesting. Initial equity grants follow a 4-year vesting schedule with a 1-year cliff (25% at 12 months,\nStrategic Retention Bonus Pools To prevent poaching of top technical architects and business leaders, the Executive Committee authorizes retention bonus packages: Retention Grants: Cash bonuses paid over a 2-year retention window with 50% milestone at month 12 and 50% at month 24. Accelerated Vesting: In double-trigger change-of-control events, designated key personnel receive 100% immediate acceleration of unvested equity. 3. Key-Person Life	answered	\N	gemini	\N	\N	2026-10-06 16:31:21.26536+05:30
5fc44b4b-55cf-45db-9b97-c557a1dc6698	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0b2ff35e-c149-46a3-ad34-e3a398018faa	user	Write Java code for binary search algorithm.	answered	\N	\N	\N	\N	2026-10-06 16:31:21.370189+05:30
598d6064-5656-48dc-8e26-457eeed8e12c	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0b2ff35e-c149-46a3-ad34-e3a398018faa	assistant	I do not have enough information in the accessible documents to answer this question.	refused	\N	gemini	\N	\N	2026-10-06 16:31:21.370189+05:30
fdabeef0-8545-4a8b-87b2-08deff972fb0	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f9352fcf-70b3-47ff-a30f-90a7628e2ae8	user	Where are fire emergency assembly points?	answered	\N	\N	\N	\N	2026-10-06 16:31:21.464464+05:30
ea521b48-f613-4bfe-828f-371c1594ea26	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	f9352fcf-70b3-47ff-a30f-90a7628e2ae8	assistant	Workplace Safety and Emergency Procedures 1. Emergency Evacuation In the event of a fire alarm or emergency evacuation: Immediately stop work and proceed calmly to the nearest designated emergency exit stairwell. Do not use elevators during a fire evacuation. Assemble at the Designated Assembly Point located in the North Parking Plaza and check in with your Floor Safety Warden. 2. Medical Emergencies and First Aid First aid kits and Automated	answered	\N	gemini	\N	\N	2026-10-06 16:31:21.464464+05:30
c94f0913-e182-4703-b45b-66d1b6c58f7a	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	d78197d1-2f1d-42df-8d4a-21e49472cab0	user	What is the annual leave and PTO rollover policy?	answered	\N	\N	\N	\N	2026-10-06 22:02:02.663656+05:30
c76ee660-03f2-4565-a808-4a899809e402	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	d78197d1-2f1d-42df-8d4a-21e49472cab0	assistant	# Annual Leave and Paid Time Off (PTO) Guidelines ## 1. PTO Accrual Full-time employees accrue 20 days of paid vacation per calendar year (1.67 days per month). Employees with over 5 years of tenure accrue 25 days annually. ## 2. Sick Leave Employees receive 10 paid sick days per year, allotted on January 1st. Sick leave does not carry over across calendar years and is not paid out upon separation. ## 3. Rollover Policy A maximum of 5 unused\nis not paid out upon separation. ## 3. Rollover Policy A maximum of 5 unused vacation days may be rolled over into the subsequent calendar year. Rolled-over days must be utilized by March 31st of the new year, after which they expire. ## 4. Parental and Bereavement Leave Primary caregivers receive 16 weeks of fully paid parental leave. Secondary caregivers receive 8 weeks of fully paid parental leave. Bereavement leave provides up to 5\n8 weeks of fully paid parental leave. Bereavement leave provides up to 5 consecutive paid days for immediate family members.	answered	\N	gemini	\N	\N	2026-10-06 22:02:02.663656+05:30
bda9166e-1ec3-42f0-a614-a7c97198f8bd	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	5bcb3c80-ce35-4c0d-af12-a5ee2e8f8732	user	What are the executive salary bands and bonus multipliers?	answered	\N	\N	\N	\N	2026-10-06 22:02:02.797224+05:30
cf333f01-c42c-4fd8-bf3d-6845c21ad155	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	5bcb3c80-ce35-4c0d-af12-a5ee2e8f8732	assistant	I do not have enough information in the accessible documents to answer this question.	refused	\N	gemini	\N	\N	2026-10-06 22:02:02.797224+05:30
e5f1b812-33ea-4858-8592-bdb3002d6477	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0630674b-98bc-4154-9da8-eced48fad12f	user	What are the executive salary bands and bonus multipliers?	answered	\N	\N	\N	\N	2026-10-06 22:02:02.930936+05:30
084aa3c0-ff4f-409f-8879-efc807074a55	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	0630674b-98bc-4154-9da8-eced48fad12f	assistant	HR Confidential: Executive Salary Bands and Equity Matrix --- Page 1 --- HR CONFIDENTIAL - Compensation Structure 2026. Section 1: Level Grades and Base Salary Ranges. L3 Associate: $85,000 - $115,000. L4 Mid-Level: $115,000 - $155,000. L5 Senior: $155,000 - $205,000. L6 Staff / Principal: $205,000 - $265,000. L7 Director: $265,000 - $340,000. L8 Vice President: $340,000 - $450,000 base. --- Page 2 --- Section 2: Annual Incentive Bonus Target\n- $450,000 base. --- Page 2 --- Section 2: Annual Incentive Bonus Target Percentages. L3-L4 target bonus: 10% of base salary. L5 target bonus: 15% of base salary. L6 target bonus: 20% of base salary. L7-L8 executive bonus: 30% to 40% based on company ARR growth and EBITDA targets. --- Page 3 --- Section 3: Equity Grant Guidelines and RSU Vesting. Initial equity grants follow a 4-year vesting schedule with a 1-year cliff (25% at 12 months,\nStrategic Retention Bonus Pools To prevent poaching of top technical architects and business leaders, the Executive Committee authorizes retention bonus packages: Retention Grants: Cash bonuses paid over a 2-year retention window with 50% milestone at month 12 and 50% at month 24. Accelerated Vesting: In double-trigger change-of-control events, designated key personnel receive 100% immediate acceleration of unvested equity. 3. Key-Person Life	answered	\N	gemini	\N	\N	2026-10-06 22:02:02.930936+05:30
834f0357-eb23-46c5-96f2-bb98ea60df35	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	ed69c5e5-33cf-4637-82b8-6266266fe490	user	Write Java code for binary search algorithm.	answered	\N	\N	\N	\N	2026-10-06 22:02:03.071786+05:30
0487437d-df9d-4a5b-8d8b-8fa7c08ff5d5	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	ed69c5e5-33cf-4637-82b8-6266266fe490	assistant	I do not have enough information in the accessible documents to answer this question.	refused	\N	gemini	\N	\N	2026-10-06 22:02:03.071786+05:30
db7afd00-02c2-4bc1-85a3-b5125fa3aebd	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	14bac758-65fd-45fe-b904-ce7ad0336235	user	Where are fire emergency assembly points?	answered	\N	\N	\N	\N	2026-10-06 22:02:03.205664+05:30
0ae65968-99c8-4376-a7c1-0b67cea2dc99	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	14bac758-65fd-45fe-b904-ce7ad0336235	assistant	Workplace Safety and Emergency Procedures 1. Emergency Evacuation In the event of a fire alarm or emergency evacuation: Immediately stop work and proceed calmly to the nearest designated emergency exit stairwell. Do not use elevators during a fire evacuation. Assemble at the Designated Assembly Point located in the North Parking Plaza and check in with your Floor Safety Warden. 2. Medical Emergencies and First Aid First aid kits and Automated	answered	\N	gemini	\N	\N	2026-10-06 22:02:03.205664+05:30
c1630aec-0bae-49f8-a5f6-391335acbd89	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	4bd9ad22-4314-42b3-8cf9-cf4b860b2b1f	user	What is our annual leave and PTO rollover policy?	answered	\N	\N	\N	\N	2026-10-06 22:12:16.851596+05:30
673f31f1-0f37-42fe-bcf8-5585cc32febb	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	4bd9ad22-4314-42b3-8cf9-cf4b860b2b1f	assistant	# Annual Leave and Paid Time Off (PTO) Guidelines ## 1. PTO Accrual Full-time employees accrue 20 days of paid vacation per calendar year (1.67 days per month). Employees with over 5 years of tenure accrue 25 days annually. ## 2. Sick Leave Employees receive 10 paid sick days per year, allotted on January 1st. Sick leave does not carry over across calendar years and is not paid out upon separation. ## 3. Rollover Policy A maximum of 5 unused\nis not paid out upon separation. ## 3. Rollover Policy A maximum of 5 unused vacation days may be rolled over into the subsequent calendar year. Rolled-over days must be utilized by March 31st of the new year, after which they expire. ## 4. Parental and Bereavement Leave Primary caregivers receive 16 weeks of fully paid parental leave. Secondary caregivers receive 8 weeks of fully paid parental leave. Bereavement leave provides up to 5\n8 weeks of fully paid parental leave. Bereavement leave provides up to 5 consecutive paid days for immediate family members.\n4:00 PM in the employee's designated local timezone. Flexible schedules must be agreed upon with direct team managers. ## 3. Remote and Hybrid Work Policy Employees may work remotely up to 3 days per week. Remote workers must maintain a secure, high-speed internet connection (minimum 50 Mbps) and adhere to IT security protocols. Fully remote status requires VP approval. ## 4. Code of Conduct and Anti-Harassment Enterprise Corporation strictly	answered	\N	gemini	\N	\N	2026-10-06 22:12:16.851596+05:30
\.


--
-- Data for Name: permissions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.permissions (code, description) FROM stdin;
chat.use	Ask questions
document.read	Read documents (still subject to document ACL)
document.upload	Upload documents to a project
document.approve	Approve / reject document versions
document.delete	Delete documents
document.acl.manage	Add restrictive ACL overrides
project.manage	Edit project settings
project.members.manage	Manage project membership
feedback.review	Review answer feedback
admin.users.manage	Manage users, groups and roles
admin.connectors.manage	Manage source connectors
admin.policies.manage	Manage ABAC / governance policies
admin.audit.read	Read audit logs
\.


--
-- Data for Name: pii_findings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pii_findings (id, tenant_id, version_id, chunk_id, pii_type, start_offset, end_offset, value_hash, action) FROM stdin;
\.


--
-- Data for Name: projects; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.projects (id, tenant_id, key, name, description, status, default_classification, require_approval, owner_user_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: query_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.query_logs (id, user_id, team_id, session_id, query, response, retrieved_document_ids, citations_json, created_at) FROM stdin;
4	61bdc8eb-3dd9-4383-9c10-91bb052e7207	\N	sess-390afdb45a97	what is work from home policy	Nexora Technologies follows a hybrid work policy (Document ID NXR-HR-POL-003) effective April 1, 2026, which generally consists of three days in the office and two days working from home (WFH) each week [Source 1]. WFH is considered a facility rather than an entitlement and may be withdrawn for performance or conduct reasons [Source 2].\n\n**Eligibility**\n*   **Confirmed Employees:** Eligible for the standard hybrid model of 2 WFH days per week [Source 1].\n*   **Employees on Probation:** Eligible for up to 1 WFH day per week with manager approval [Source 2].\n*   **Interns and Trainees:** Generally office-based, with WFH allowed only for exceptions [Source 2].\n*   **Specific Roles:** Roles requiring physical presence (e.g., IT Admin, Reception) are not eligible unless approved by HR [Source 2].\n*   **Remote Roles:** Only permitted if specified in the employee's offer letter [Source 2].\n\n**Approval and Location Requirements**\n*   **Standard Hybrid:** Teams agree on fixed "anchor days" in the office; no daily approval is required for these days [Source 2].\n*   **Extra WFH Days:** Employees may request up to 10 additional WFH days per year via PeopleHub with at least one working day's notice [Source 2].\n*   **Extended WFH:** Requests for more than two weeks (maximum 8 weeks) require written approval from a manager and HR Business Partner [Source 2].\n*   **Location Restrictions:** Working from another city or state requires HR and IT Security approval. Working outside of India is not permitted without Legal, HR, and Finance approval [Source 2].\n\n**Working Hours and Expectations**\n*   **Availability:** Employees must be online during core hours (11:00 AM – 4:00 PM), with total daily working hours remaining at eight [Source 2].\n*   **Attendance:** Attendance must be marked at the start and end of the day using PeopleHub Mobile [Source 2].\n*   **Performance:** WFH days may be reduced if sprint commitments are repeatedly missed or if an employee is unreachable during core hours [Source 3].\n*   **Client Overrides:** Client contracts mandating on-site presence override this policy for the specific team members involved [Source 3].\n\n**Security and Safety**\n*   **Data Security:** Employees must use the Nexora VPN (GlobalProtect) and maintain data security standards, including encrypted VPN and secure Wi-Fi [Source 4, Source 5].\n*   **Workspace Safety:** Employees are responsible for maintaining a safe, ergonomic workspace. Any injuries occurring during WFH hours must be reported to HR within 24 hours [Source 3].	["doc-f34d3b0e0c4d", "doc-fd7fd7ba8702", "doc-2fef237a53e6"]	[{"document_id": "doc-f34d3b0e0c4d", "document_name": "Work_From_Home_Policy.pdf", "chunk_index": 0, "text": "Nexora Technologies Pvt. Ltd.\\nWork From Home (Hybrid Work) Policy\\nDocument ID NXR-HR-POL-003\\nVersion 2.1\\nEffective Date 1 April 2026\\nOwner Head of HR with CTO (Sanjay Kulkarni)\\nApplies To Eligible employees in India offices\\n1. Purpose\\nNexora follows a hybrid model: three days in office and two days from\\nhome each week. This policy explains who can work from home (WFH),\\nhow to request it, expected working hours, equipment support and\\nproductivity expectations.\\n2. Eligibility\\nCategory Eligibility\\nConfirmed employees (all levels) Standard hybrid: 2 WFH\\ndays per week", "score": 0.7669, "page_start": 1, "page_end": 1, "section_path": "Page 1", "chunk_id": "225cd5b9-28da-4586-9a3c-8a89c11d8e06"}, {"document_id": "doc-f34d3b0e0c4d", "document_name": "Work_From_Home_Policy.pdf", "chunk_index": 1, "text": "Employees on probation Up to 1 WFH day per week,\\nwith manager approval\\nInterns and trainees Office-based; WFH only for\\nexceptions\\nRoles needing physical presence (IT Not eligible unless\\nAdmin, Facilities, Hardware Lab, approved by HR\\nReception)\\nFully remote roles Only if stated in offer letter\\n(currently 14 employees)\\nWFH is a facility, not an entitlement, and may be withdrawn for\\nperformance or conduct reasons after written notice.\\n3. Approval Process\\n1. Standard hybrid days: Teams agree a fixed anchor day in office\\n(for example, Tuesday and Thursday for Project Atlas squads). No\\nper-day approval is needed.\\n2. Extra WFH days (up to 10 per year): Request in PeopleHub at\\nleast 1 working day ahead. Manager approves.\\n3. Extended WFH (more than 2 weeks, for example, medical or\\nrelocation): Written request to manager and HR Business\\nPartner. Maximum 8 weeks, renewable once.\\n4. Working from another city or state: Needs HR and IT Security\\napproval for tax, labour-law and data-security reasons.\\n5. Working from outside India: Not permitted without Legal, HR\\nand Finance approval.\\n4. Working Hours and Availability\\n\\u2022 Be available online 11:00 AM \\u2013 4:00 PM (core hours) on WFH\\ndays; total working hours remain 8.\\n\\u2022 Mark attendance on PeopleHub Mobile at start and end of day.", "score": 0.7529, "page_start": 2, "page_end": 2, "section_path": "Page 2", "chunk_id": "2465f8b0-ea46-4fbb-abb4-ad0102faf820"}, {"document_id": "doc-f34d3b0e0c4d", "document_name": "Work_From_Home_Policy.pdf", "chunk_index": 3, "text": "session.\\n\\u2022 If sprint commitments are repeatedly missed or a person is\\nunreachable during core hours, the manager may reduce WFH\\ndays after discussion and a written note to HR.\\n\\u2022 Client contracts that mandate on-site presence (for example, the\\nMeridian programme for a banking client) override this policy for\\nnamed team members.\\nExample: Neha (Engineer, L2) is on the Atlas payments squad. Her\\nsquad's anchor days are Tuesday and Wednesday, and she chooses\\nThursday as her third office day. She works from home on Monday and\\nFriday. If she wants to work from home on Thursday as well, she raises\\nan extra WFH request in PeopleHub one working day ahead, and it\\ncounts towards her 10 extra days for the year.\\n7. Health and Safety\\nEmployees are responsible for a safe, ergonomic workspace. Injuries\\noccurring during working hours at home should be reported to HR within\\n24 hours.\\n8. Policy Review\\nThe policy is reviewed annually in March. Feedback can be sent to\\nhr@nexora-tech.example.", "score": 0.7399, "page_start": 4, "page_end": 4, "section_path": "Page 4", "chunk_id": "9ee161ba-6bdc-4912-9ffa-1e58cd9e47fc"}, {"document_id": "doc-2fef237a53e6", "document_name": "HR_Employee_Handbook_2026.txt", "chunk_index": 5, "text": "2.2 Hybrid & Remote Work Guidelines:\\n- Employees are eligible for hybrid work (up to 3 days remote per week) subject to manager approval.\\n- Remote work environments must maintain data security standards (encrypted VPN, secure Wi-Fi).\\n- Core availability on company Slack/Teams is required during scheduled work hours.", "score": 0.7129, "page_start": 1, "page_end": 1, "section_path": "2.2 Hybrid & Remote Work Guidelines:", "chunk_id": "4203e20c-3c16-4165-b173-633257e37bf4"}, {"document_id": "doc-fd7fd7ba8702", "document_name": "Remote_Work_Security_Guidelines.pdf", "chunk_index": 0, "text": "Nexora Technologies Pvt. Ltd.\\nRemote Work Security Guidelines\\nDocument NXR-IT-GDL-008\\nID\\nVersion 2.5\\nEffective 1 April 2026\\nDate\\nOwner Information Security Office (CISO: Dr. Farhan\\nQureshi)\\nApplies To All employees, contractors and interns working\\noutside Nexora offices\\n1. Purpose\\nTo protect Nexora and client data when employees work from home,\\nclient sites, travel or any non-office location. These guidelines support\\nISO 27001 requirements and client security clauses (for example, those\\nin the Project Meridian banking contract).\\n2. VPN Usage\\n\\u2022 Connect to the Nexora VPN (GlobalProtect) before accessing\\nany internal system, code repository, staging environment or client", "score": 0.7058, "page_start": 1, "page_end": 1, "section_path": "Page 1", "chunk_id": "5020cc9a-e424-41a0-bb1e-e0129c931d85"}]	2026-10-07 19:11:49.012658
5	61bdc8eb-3dd9-4383-9c10-91bb052e7207	\N	sess-390afdb45a97	Who needs to approve international travel for an L5 employee?	For an L5 employee, international travel must be approved by the following:\n*   Department Head [Source 1]\n*   Finance Controller [Source 1]\n*   CFO (required for L5 and above) [Source 1]	["doc-21379031a248", "doc-27eadc26a7a2"]	[{"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 1, "text": "Domestic, more Manager + Department Head 5 working days\\nthan 3 days\\nInternational Department Head + Finance 15 working days\\nController; CFO approval for (visa and\\nL5 and above booking)\\nClient-mandated Manager (client email As per client\\ntravel attached) need\\nRaise a request on PeopleHub \\u2192 Travel. Bookings are made only\\nthrough the Nexora Travel Desk (travel@nexora-tech.example) or the\\napproved booking tool. Non-approved travel is not reimbursed.\\n3. Transportation\\nMode Entitlement\\nAir (domestic) Economy class; book at least 7 days ahead; lowest\\nlogical fare\\nAir Economy; Premium Economy for flights over 8\\n(international) hours, L5 and above\\nTrain AC 2-tier (L1\\u2013L4); AC 1st class or Executive Chair\\n(L5+)\\nLocal travel Metro/bus or app-based cab (Mini/Sedan); auto-\\nrickshaw for short distance\\nPersonal car \\u20b912 per km; bike \\u20b95 per km, with a log of distance,\\npurpose and parking/toll bills\\nAirport Cab as per local travel rules\\ntransfers\\nCancellation charges resulting from a personal reason are borne by the\\nemployee.", "score": 0.7831, "page_start": 2, "page_end": 2, "section_path": "Page 2", "chunk_id": "cf05d0a1-6f8f-46ed-9f6f-7d6c0b80dddb"}, {"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 0, "text": "Nexora Technologies Pvt. Ltd.\\nTravel and Expense Policy\\nDocument NXR-FIN-POL-013\\nID\\nVersion 3.0\\nEffective 1 April 2026\\nDate\\nOwner Finance (Controller: Ramesh Patil) with Admin &\\nTravel Desk\\nApplies To All employees travelling on company business\\n1. Purpose\\nTo ensure business travel is approved, cost-effective and properly\\ndocumented, and that reimbursements are fair and prompt.\\n2. Business Travel Approval\\nTravel Type Approver Lead Time\\nDomestic, up to Reporting Manager 3 working days\\n3 days", "score": 0.7374, "page_start": 1, "page_end": 1, "section_path": "Page 1", "chunk_id": "d0b5b548-eeb4-4fe6-bd38-e1f74f62ceac"}, {"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 3, "text": "Visa and travel insurance (international), airport lounge (only if included\\nin card/ticket), Wi-Fi/data when travelling (up to \\u20b9500 per trip), and\\nparking and toll charges. Not eligible: fines, personal shopping, mini-\\nbar, in-room entertainment, personal phone calls, or upgrades without\\napproval.\\n7. Advances\\nUp to 75% of estimated cost can be requested 5 working days before\\ntravel. Unused advance must be returned or settled within 10 days of\\nreturn.\\n8. Reimbursement Process\\n1. File the expense report on PeopleHub \\u2192 Expenses within 15\\ndays of return (claims after 45 days are rejected).\\n2. Attach original receipts for each item above \\u20b9300; GST invoices in\\nthe company name where available.\\n3. Manager approves within 3 working days.\\n4. Finance validates policy compliance and pays within 7 working\\ndays of approval with the next payroll or by bank transfer.\\n5. Exceptions (over-limit spending) need Department Head approval\\nbefore the trip.\\nExample: Sameer (Lead Engineer, L4) travels from Pune to Bengaluru\\non 12\\u201314 August for a Meridian client workshop. Approved by manager\\nand Department Head. Economy flight \\u20b95,800; hotel 2 nights at \\u20b97,200\\nper night; meals 3 days at \\u20b91,000 per day; cabs \\u20b91,350. Total \\u20b924,550.\\nHe files the claim on 18 August with receipts, and Finance reimburses it\\non 28 August.\\n9. Compliance", "score": 0.7288, "page_start": 4, "page_end": 4, "section_path": "Page 4", "chunk_id": "9a5df0d4-4725-40b3-ae92-546278b6735d"}, {"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 2, "text": "4. Accommodation\\nCity Tier L1\\u2013L3 L4\\u2013L5 L6 and\\nabove\\nTier 1 (Mumbai, Delhi NCR, \\u20b95,500 \\u20b97,500 \\u20b910,000\\nBengaluru, Hyderabad, Pune, per night\\nChennai)\\nTier 2 (Ahmedabad, Jaipur, Kochi, \\u20b94,000 \\u20b95,500 \\u20b97,500\\netc.)\\nInternational Up to $200 $300\\n$150\\nHotels should be on the approved list where possible. Stay with friends\\nor family is not reimbursed. Laundry is allowed for stays of 4 or more\\nnights up to \\u20b9500.\\n5. Meals and Daily Allowance (Per Diem)\\nLocation Daily Meal Breakdown\\nLimit\\nTier 1 city \\u20b91,200 Breakfast \\u20b9250, Lunch \\u20b9400, Dinner\\n\\u20b9550\\nTier 2 / \\u20b9900 Breakfast \\u20b9200, Lunch \\u20b9300, Dinner\\nother \\u20b9400\\nInternational $45 As per country guide\\nAlcohol is not reimbursable. Client entertainment up to \\u20b92,500 per\\nperson needs pre-approval and must list attendees and purpose.\\n6. Other Eligible Expenses", "score": 0.7048, "page_start": 3, "page_end": 3, "section_path": "Page 3", "chunk_id": "6048159c-4bc1-4258-a0c5-24a512f8eca9"}, {"document_id": "doc-21379031a248", "document_name": "Promotion_and_Career_Growth_Guidelines.pdf", "chunk_index": 1, "text": "L2 Engineer 2\\u20134 years Delivers features\\nindependently\\nL3 Senior Engineer 4\\u20137 years Owns modules;\\nmentors juniors\\nL4 Lead Engineer 7\\u201310 years Leads a squad; drives\\ndesign and delivery\\nL5 Principal Engineer 10\\u201314 years Owns product area or\\n/ Engineering multiple squads\\nManager\\nL6 Director 14+ years Owns a business unit\\nor programme (for\\nexample, Atlas)\\nL7 VP / Head 18+ years Sets strategy across\\nunits\\nExperience is indicative. Promotion depends on demonstrated capability,\\nnot years alone. Non-engineering functions (QA, Product, HR, Finance,\\nSales) use the same levels with function-specific titles.\\nThere are two growth tracks from L4: Technical (Principal,\\nDistinguished Engineer) and Management (Manager, Director).\\nEmployees may switch tracks once, with approval.\\n3. Promotion Criteria\\nCriterion What We Look For\\nPerformance Rating of 4 or above in the last cycle and 3 or\\nabove in the one before; no active warning or\\nPIP\\nMinimum tenure L1\\u2192L2: 18 months; L2\\u2192L3: 24 months; L3\\u2192L4:\\nin level 30 months; L4\\u2192L5: 36 months\\nReadiness at next Already performing at least 70% of the\\nlevel responsibilities of the next level for 6 months", "score": 0.6958, "page_start": 2, "page_end": 2, "section_path": "Page 2", "chunk_id": "29d6284e-500d-4c44-b75e-7660e438c9d7"}]	2026-10-07 19:14:51.708464
6	61bdc8eb-3dd9-4383-9c10-91bb052e7207	\N	sess-fde513675068	How many working days in advance must international travel be approved?	International travel must be approved 15 working days in advance for visa and booking [Source 1].	["doc-68237f22039b", "doc-2fef237a53e6", "doc-27eadc26a7a2"]	[{"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 1, "text": "Domestic, more Manager + Department Head 5 working days\\nthan 3 days\\nInternational Department Head + Finance 15 working days\\nController; CFO approval for (visa and\\nL5 and above booking)\\nClient-mandated Manager (client email As per client\\ntravel attached) need\\nRaise a request on PeopleHub \\u2192 Travel. Bookings are made only\\nthrough the Nexora Travel Desk (travel@nexora-tech.example) or the\\napproved booking tool. Non-approved travel is not reimbursed.\\n3. Transportation\\nMode Entitlement\\nAir (domestic) Economy class; book at least 7 days ahead; lowest\\nlogical fare\\nAir Economy; Premium Economy for flights over 8\\n(international) hours, L5 and above\\nTrain AC 2-tier (L1\\u2013L4); AC 1st class or Executive Chair\\n(L5+)\\nLocal travel Metro/bus or app-based cab (Mini/Sedan); auto-\\nrickshaw for short distance\\nPersonal car \\u20b912 per km; bike \\u20b95 per km, with a log of distance,\\npurpose and parking/toll bills\\nAirport Cab as per local travel rules\\ntransfers\\nCancellation charges resulting from a personal reason are borne by the\\nemployee.", "score": 0.7449, "page_start": 2, "page_end": 2, "section_path": "Page 2", "chunk_id": "cf05d0a1-6f8f-46ed-9f6f-7d6c0b80dddb"}, {"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 0, "text": "Nexora Technologies Pvt. Ltd.\\nTravel and Expense Policy\\nDocument NXR-FIN-POL-013\\nID\\nVersion 3.0\\nEffective 1 April 2026\\nDate\\nOwner Finance (Controller: Ramesh Patil) with Admin &\\nTravel Desk\\nApplies To All employees travelling on company business\\n1. Purpose\\nTo ensure business travel is approved, cost-effective and properly\\ndocumented, and that reimbursements are fair and prompt.\\n2. Business Travel Approval\\nTravel Type Approver Lead Time\\nDomestic, up to Reporting Manager 3 working days\\n3 days", "score": 0.7283, "page_start": 1, "page_end": 1, "section_path": "Page 1", "chunk_id": "d0b5b548-eeb4-4fe6-bd38-e1f74f62ceac"}, {"document_id": "doc-2fef237a53e6", "document_name": "HR_Employee_Handbook_2026.txt", "chunk_index": 6, "text": "--------------------------------------------------------------------------------\\n3. LEAVE & VACATION POLICY\\n--------------------------------------------------------------------------------\\n3.1 Paid Time Off (PTO):\\n- Full-time employees accrue 22 business days of PTO annually.\\n- Unused PTO up to 5 days can be carried over into the next calendar year.", "score": 0.675, "page_start": 1, "page_end": 1, "section_path": "2.2 Hybrid & Remote Work Guidelines:", "chunk_id": "569a74c9-334d-4387-b1dd-03d0ff574750"}, {"document_id": "doc-68237f22039b", "document_name": "Employee_Leave_Policy.pdf", "chunk_index": 5, "text": "3.2 1 April EL carry-forward cap raised from 24 to 30\\n2026 days", "score": 0.6729, "page_start": 6, "page_end": 6, "section_path": "Page 6", "chunk_id": "8a6d2b18-c208-4c1c-ac69-a217f133fe44"}, {"document_id": "doc-2fef237a53e6", "document_name": "HR_Employee_Handbook_2026.txt", "chunk_index": 5, "text": "2.2 Hybrid & Remote Work Guidelines:\\n- Employees are eligible for hybrid work (up to 3 days remote per week) subject to manager approval.\\n- Remote work environments must maintain data security standards (encrypted VPN, secure Wi-Fi).\\n- Core availability on company Slack/Teams is required during scheduled work hours.", "score": 0.6649, "page_start": 1, "page_end": 1, "section_path": "2.2 Hybrid & Remote Work Guidelines:", "chunk_id": "4203e20c-3c16-4165-b173-633257e37bf4"}]	2026-10-07 19:16:10.120564
7	61bdc8eb-3dd9-4383-9c10-91bb052e7207	\N	sess-390afdb45a97	who needs to approve international travel for an L5 employee?	For an L5 employee, international travel must be approved by the following:\n\n*   **Department Head** [Source 1]\n*   **Finance Controller** [Source 1]\n*   **CFO** (required for L5 and above) [Source 1]	["doc-27eadc26a7a2", "doc-21379031a248"]	[{"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 1, "text": "Domestic, more Manager + Department Head 5 working days\\nthan 3 days\\nInternational Department Head + Finance 15 working days\\nController; CFO approval for (visa and\\nL5 and above booking)\\nClient-mandated Manager (client email As per client\\ntravel attached) need\\nRaise a request on PeopleHub \\u2192 Travel. Bookings are made only\\nthrough the Nexora Travel Desk (travel@nexora-tech.example) or the\\napproved booking tool. Non-approved travel is not reimbursed.\\n3. Transportation\\nMode Entitlement\\nAir (domestic) Economy class; book at least 7 days ahead; lowest\\nlogical fare\\nAir Economy; Premium Economy for flights over 8\\n(international) hours, L5 and above\\nTrain AC 2-tier (L1\\u2013L4); AC 1st class or Executive Chair\\n(L5+)\\nLocal travel Metro/bus or app-based cab (Mini/Sedan); auto-\\nrickshaw for short distance\\nPersonal car \\u20b912 per km; bike \\u20b95 per km, with a log of distance,\\npurpose and parking/toll bills\\nAirport Cab as per local travel rules\\ntransfers\\nCancellation charges resulting from a personal reason are borne by the\\nemployee.", "score": 0.7752, "page_start": 2, "page_end": 2, "section_path": "Page 2", "chunk_id": "cf05d0a1-6f8f-46ed-9f6f-7d6c0b80dddb"}, {"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 0, "text": "Nexora Technologies Pvt. Ltd.\\nTravel and Expense Policy\\nDocument NXR-FIN-POL-013\\nID\\nVersion 3.0\\nEffective 1 April 2026\\nDate\\nOwner Finance (Controller: Ramesh Patil) with Admin &\\nTravel Desk\\nApplies To All employees travelling on company business\\n1. Purpose\\nTo ensure business travel is approved, cost-effective and properly\\ndocumented, and that reimbursements are fair and prompt.\\n2. Business Travel Approval\\nTravel Type Approver Lead Time\\nDomestic, up to Reporting Manager 3 working days\\n3 days", "score": 0.7322, "page_start": 1, "page_end": 1, "section_path": "Page 1", "chunk_id": "d0b5b548-eeb4-4fe6-bd38-e1f74f62ceac"}, {"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 3, "text": "Visa and travel insurance (international), airport lounge (only if included\\nin card/ticket), Wi-Fi/data when travelling (up to \\u20b9500 per trip), and\\nparking and toll charges. Not eligible: fines, personal shopping, mini-\\nbar, in-room entertainment, personal phone calls, or upgrades without\\napproval.\\n7. Advances\\nUp to 75% of estimated cost can be requested 5 working days before\\ntravel. Unused advance must be returned or settled within 10 days of\\nreturn.\\n8. Reimbursement Process\\n1. File the expense report on PeopleHub \\u2192 Expenses within 15\\ndays of return (claims after 45 days are rejected).\\n2. Attach original receipts for each item above \\u20b9300; GST invoices in\\nthe company name where available.\\n3. Manager approves within 3 working days.\\n4. Finance validates policy compliance and pays within 7 working\\ndays of approval with the next payroll or by bank transfer.\\n5. Exceptions (over-limit spending) need Department Head approval\\nbefore the trip.\\nExample: Sameer (Lead Engineer, L4) travels from Pune to Bengaluru\\non 12\\u201314 August for a Meridian client workshop. Approved by manager\\nand Department Head. Economy flight \\u20b95,800; hotel 2 nights at \\u20b97,200\\nper night; meals 3 days at \\u20b91,000 per day; cabs \\u20b91,350. Total \\u20b924,550.\\nHe files the claim on 18 August with receipts, and Finance reimburses it\\non 28 August.\\n9. Compliance", "score": 0.715, "page_start": 4, "page_end": 4, "section_path": "Page 4", "chunk_id": "9a5df0d4-4725-40b3-ae92-546278b6735d"}, {"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 2, "text": "4. Accommodation\\nCity Tier L1\\u2013L3 L4\\u2013L5 L6 and\\nabove\\nTier 1 (Mumbai, Delhi NCR, \\u20b95,500 \\u20b97,500 \\u20b910,000\\nBengaluru, Hyderabad, Pune, per night\\nChennai)\\nTier 2 (Ahmedabad, Jaipur, Kochi, \\u20b94,000 \\u20b95,500 \\u20b97,500\\netc.)\\nInternational Up to $200 $300\\n$150\\nHotels should be on the approved list where possible. Stay with friends\\nor family is not reimbursed. Laundry is allowed for stays of 4 or more\\nnights up to \\u20b9500.\\n5. Meals and Daily Allowance (Per Diem)\\nLocation Daily Meal Breakdown\\nLimit\\nTier 1 city \\u20b91,200 Breakfast \\u20b9250, Lunch \\u20b9400, Dinner\\n\\u20b9550\\nTier 2 / \\u20b9900 Breakfast \\u20b9200, Lunch \\u20b9300, Dinner\\nother \\u20b9400\\nInternational $45 As per country guide\\nAlcohol is not reimbursable. Client entertainment up to \\u20b92,500 per\\nperson needs pre-approval and must list attendees and purpose.\\n6. Other Eligible Expenses", "score": 0.6928, "page_start": 3, "page_end": 3, "section_path": "Page 3", "chunk_id": "6048159c-4bc1-4258-a0c5-24a512f8eca9"}, {"document_id": "doc-21379031a248", "document_name": "Promotion_and_Career_Growth_Guidelines.pdf", "chunk_index": 1, "text": "L2 Engineer 2\\u20134 years Delivers features\\nindependently\\nL3 Senior Engineer 4\\u20137 years Owns modules;\\nmentors juniors\\nL4 Lead Engineer 7\\u201310 years Leads a squad; drives\\ndesign and delivery\\nL5 Principal Engineer 10\\u201314 years Owns product area or\\n/ Engineering multiple squads\\nManager\\nL6 Director 14+ years Owns a business unit\\nor programme (for\\nexample, Atlas)\\nL7 VP / Head 18+ years Sets strategy across\\nunits\\nExperience is indicative. Promotion depends on demonstrated capability,\\nnot years alone. Non-engineering functions (QA, Product, HR, Finance,\\nSales) use the same levels with function-specific titles.\\nThere are two growth tracks from L4: Technical (Principal,\\nDistinguished Engineer) and Management (Manager, Director).\\nEmployees may switch tracks once, with approval.\\n3. Promotion Criteria\\nCriterion What We Look For\\nPerformance Rating of 4 or above in the last cycle and 3 or\\nabove in the one before; no active warning or\\nPIP\\nMinimum tenure L1\\u2192L2: 18 months; L2\\u2192L3: 24 months; L3\\u2192L4:\\nin level 30 months; L4\\u2192L5: 36 months\\nReadiness at next Already performing at least 70% of the\\nlevel responsibilities of the next level for 6 months", "score": 0.6787, "page_start": 2, "page_end": 2, "section_path": "Page 2", "chunk_id": "29d6284e-500d-4c44-b75e-7660e438c9d7"}]	2026-10-08 20:20:21.996904
8	61bdc8eb-3dd9-4383-9c10-91bb052e7207	\N	sess-390afdb45a97	How many working days in advance must international travel be approved?	International travel must be approved 15 working days in advance to allow for visa processing and booking [Source 1].	["doc-27eadc26a7a2", "doc-2fef237a53e6", "doc-68237f22039b"]	[{"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 1, "text": "Domestic, more Manager + Department Head 5 working days\\nthan 3 days\\nInternational Department Head + Finance 15 working days\\nController; CFO approval for (visa and\\nL5 and above booking)\\nClient-mandated Manager (client email As per client\\ntravel attached) need\\nRaise a request on PeopleHub \\u2192 Travel. Bookings are made only\\nthrough the Nexora Travel Desk (travel@nexora-tech.example) or the\\napproved booking tool. Non-approved travel is not reimbursed.\\n3. Transportation\\nMode Entitlement\\nAir (domestic) Economy class; book at least 7 days ahead; lowest\\nlogical fare\\nAir Economy; Premium Economy for flights over 8\\n(international) hours, L5 and above\\nTrain AC 2-tier (L1\\u2013L4); AC 1st class or Executive Chair\\n(L5+)\\nLocal travel Metro/bus or app-based cab (Mini/Sedan); auto-\\nrickshaw for short distance\\nPersonal car \\u20b912 per km; bike \\u20b95 per km, with a log of distance,\\npurpose and parking/toll bills\\nAirport Cab as per local travel rules\\ntransfers\\nCancellation charges resulting from a personal reason are borne by the\\nemployee.", "score": 0.7449, "page_start": 2, "page_end": 2, "section_path": "Page 2", "chunk_id": "cf05d0a1-6f8f-46ed-9f6f-7d6c0b80dddb"}, {"document_id": "doc-27eadc26a7a2", "document_name": "Travel_and_Expense_Policy.pdf", "chunk_index": 0, "text": "Nexora Technologies Pvt. Ltd.\\nTravel and Expense Policy\\nDocument NXR-FIN-POL-013\\nID\\nVersion 3.0\\nEffective 1 April 2026\\nDate\\nOwner Finance (Controller: Ramesh Patil) with Admin &\\nTravel Desk\\nApplies To All employees travelling on company business\\n1. Purpose\\nTo ensure business travel is approved, cost-effective and properly\\ndocumented, and that reimbursements are fair and prompt.\\n2. Business Travel Approval\\nTravel Type Approver Lead Time\\nDomestic, up to Reporting Manager 3 working days\\n3 days", "score": 0.7283, "page_start": 1, "page_end": 1, "section_path": "Page 1", "chunk_id": "d0b5b548-eeb4-4fe6-bd38-e1f74f62ceac"}, {"document_id": "doc-2fef237a53e6", "document_name": "HR_Employee_Handbook_2026.txt", "chunk_index": 6, "text": "--------------------------------------------------------------------------------\\n3. LEAVE & VACATION POLICY\\n--------------------------------------------------------------------------------\\n3.1 Paid Time Off (PTO):\\n- Full-time employees accrue 22 business days of PTO annually.\\n- Unused PTO up to 5 days can be carried over into the next calendar year.", "score": 0.675, "page_start": 1, "page_end": 1, "section_path": "2.2 Hybrid & Remote Work Guidelines:", "chunk_id": "569a74c9-334d-4387-b1dd-03d0ff574750"}, {"document_id": "doc-68237f22039b", "document_name": "Employee_Leave_Policy.pdf", "chunk_index": 5, "text": "3.2 1 April EL carry-forward cap raised from 24 to 30\\n2026 days", "score": 0.6729, "page_start": 6, "page_end": 6, "section_path": "Page 6", "chunk_id": "8a6d2b18-c208-4c1c-ac69-a217f133fe44"}, {"document_id": "doc-2fef237a53e6", "document_name": "HR_Employee_Handbook_2026.txt", "chunk_index": 5, "text": "2.2 Hybrid & Remote Work Guidelines:\\n- Employees are eligible for hybrid work (up to 3 days remote per week) subject to manager approval.\\n- Remote work environments must maintain data security standards (encrypted VPN, secure Wi-Fi).\\n- Core availability on company Slack/Teams is required during scheduled work hours.", "score": 0.6649, "page_start": 1, "page_end": 1, "section_path": "2.2 Hybrid & Remote Work Guidelines:", "chunk_id": "4203e20c-3c16-4165-b173-633257e37bf4"}]	2026-10-08 20:20:58.437802
\.


--
-- Data for Name: retrieval_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.retrieval_events (id, tenant_id, user_id, message_id, query_hash, principal_count, principal_version, filter_digest, candidates_returned, dropped_by_postcheck, selected_chunk_ids, abstained, latency_ms, created_at) FROM stdin;
\.


--
-- Data for Name: role_assignments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.role_assignments (id, tenant_id, principal_type, user_id, group_id, role_id, project_id, granted_by, expires_at, created_at, role_key, scope_type, scope_id) FROM stdin;
ef156b5a-c342-498f-bf9a-c96237ad0973	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	user	891113ac-2816-4143-ac67-f2e8684d39da	\N	fd8be805-3d32-4467-a0c2-b63f2379999f	\N	\N	\N	2026-10-06 16:11:03.185927+05:30	\N	tenant	\N
ad7f9e39-7b9b-4a14-8e73-d43ec2c2fe83	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	user	e20419bf-d2fb-46fc-ad10-97a870a8c5f5	\N	0526fb72-dad7-4d22-a3a3-287b3391cc5b	\N	\N	\N	2026-10-06 16:11:03.198436+05:30	\N	tenant	\N
\.


--
-- Data for Name: role_permissions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.role_permissions (role_id, permission) FROM stdin;
24567b65-af77-40f5-9305-065d43818806	chat.use
24567b65-af77-40f5-9305-065d43818806	document.read
24567b65-af77-40f5-9305-065d43818806	document.upload
24567b65-af77-40f5-9305-065d43818806	document.approve
24567b65-af77-40f5-9305-065d43818806	document.delete
24567b65-af77-40f5-9305-065d43818806	document.acl.manage
24567b65-af77-40f5-9305-065d43818806	project.manage
24567b65-af77-40f5-9305-065d43818806	project.members.manage
24567b65-af77-40f5-9305-065d43818806	feedback.review
24567b65-af77-40f5-9305-065d43818806	admin.users.manage
24567b65-af77-40f5-9305-065d43818806	admin.connectors.manage
24567b65-af77-40f5-9305-065d43818806	admin.policies.manage
24567b65-af77-40f5-9305-065d43818806	admin.audit.read
eec302e8-b1f5-4779-ab09-f9980182c0b6	feedback.review
eec302e8-b1f5-4779-ab09-f9980182c0b6	admin.audit.read
3dfa6574-fe71-4ec9-984c-4557a1a6fa6e	chat.use
3dfa6574-fe71-4ec9-984c-4557a1a6fa6e	document.read
c7fb0743-51e8-4373-ac90-8d69c94d33b7	chat.use
c7fb0743-51e8-4373-ac90-8d69c94d33b7	document.read
c7fb0743-51e8-4373-ac90-8d69c94d33b7	document.upload
c7fb0743-51e8-4373-ac90-8d69c94d33b7	document.approve
c7fb0743-51e8-4373-ac90-8d69c94d33b7	document.delete
c7fb0743-51e8-4373-ac90-8d69c94d33b7	project.manage
c7fb0743-51e8-4373-ac90-8d69c94d33b7	project.members.manage
b226750a-4d68-44d2-b58e-18d7d7650192	chat.use
b226750a-4d68-44d2-b58e-18d7d7650192	document.read
b226750a-4d68-44d2-b58e-18d7d7650192	document.upload
8a279c94-efb6-4430-b62a-a378ba42c7db	chat.use
8a279c94-efb6-4430-b62a-a378ba42c7db	document.read
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.roles (id, tenant_id, name, scope, is_system) FROM stdin;
24567b65-af77-40f5-9305-065d43818806	\N	tenant_admin	tenant	t
eec302e8-b1f5-4779-ab09-f9980182c0b6	\N	security_auditor	tenant	t
3dfa6574-fe71-4ec9-984c-4557a1a6fa6e	\N	employee	tenant	t
c7fb0743-51e8-4373-ac90-8d69c94d33b7	\N	project_admin	project	t
b226750a-4d68-44d2-b58e-18d7d7650192	\N	contributor	project	t
8a279c94-efb6-4430-b62a-a378ba42c7db	\N	member	project	t
fd8be805-3d32-4467-a0c2-b63f2379999f	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	HR	tenant	t
0526fb72-dad7-4d22-a3a3-287b3391cc5b	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	EMPLOYEE	tenant	t
\.


--
-- Data for Name: source_connections; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.source_connections (id, tenant_id, type, name, status, credentials_ref, config, default_project_id, content_cursor, acl_cursor, acl_lag_sla_seconds, last_synced_at, created_at) FROM stdin;
72d12445-0ba8-452e-b51c-cba11e368bac	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	manual	Enterprise Document Repository	active	\N	{}	\N	\N	\N	300	\N	2026-10-06 16:25:01.423245+05:30
bd0d053b-d32e-4b24-80cc-7860aeda120a	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	manual	Local Documents Folder	active	local_docs	{}	\N	\N	\N	300	\N	2026-10-07 11:16:23.831337+05:30
\.


--
-- Data for Name: sources; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sources (id, name, source_type, uri, drive_file_id, folder_id, status, metadata_json, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: sync_runs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sync_runs (id, tenant_id, source_connection_id, kind, status, stats, error, started_at, finished_at) FROM stdin;
fcbb26e1-d2e7-45fc-8cc7-8348f52ec33a	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bd0d053b-d32e-4b24-80cc-7860aeda120a	full	running	{}	\N	2026-10-07 11:16:23.831337+05:30	\N
3d1ffbb0-87be-43d5-8e93-4ea5c707edae	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bd0d053b-d32e-4b24-80cc-7860aeda120a	full	running	{}	\N	2026-10-07 11:16:59.484778+05:30	\N
db2f75e1-664c-4a48-9982-66d225cf3677	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bd0d053b-d32e-4b24-80cc-7860aeda120a	full	running	{}	\N	2026-10-07 11:17:43.183017+05:30	\N
4aaa56ff-5afe-4c82-a181-9538de39e5ea	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bd0d053b-d32e-4b24-80cc-7860aeda120a	full	running	{}	\N	2026-10-07 11:21:30.638752+05:30	\N
6457070b-5590-4839-b5cc-144124d32191	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bd0d053b-d32e-4b24-80cc-7860aeda120a	full	running	{}	\N	2026-10-07 11:24:04.272955+05:30	\N
71511a7e-23d8-483a-acbb-610fba9e2d5d	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bd0d053b-d32e-4b24-80cc-7860aeda120a	full	running	{}	\N	2026-10-07 11:27:09.034958+05:30	\N
2ccb89b6-ac44-42ff-ab5b-39efb4196e32	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bd0d053b-d32e-4b24-80cc-7860aeda120a	full	running	{}	\N	2026-10-07 11:29:52.815199+05:30	\N
19a34e6a-8fee-4cc1-a9fa-ab7a48d5fc25	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	bd0d053b-d32e-4b24-80cc-7860aeda120a	full	running	{}	\N	2026-10-07 11:34:28.87726+05:30	\N
\.


--
-- Data for Name: system_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.system_settings (key, value, updated_at) FROM stdin;
setup_completed	true	2026-10-07 19:00:14.210703
company_name	finTech	2026-10-07 19:00:14.210703
\.


--
-- Data for Name: team_chat_messages; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.team_chat_messages (id, team_id, user_id, user_email, message, response, citations_json, created_at) FROM stdin;
\.


--
-- Data for Name: team_members; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.team_members (id, team_id, user_id, role_in_team, joined_at) FROM stdin;
\.


--
-- Data for Name: teams; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.teams (id, name, project_name, description, created_by_id, created_at) FROM stdin;
\.


--
-- Data for Name: tenants; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tenants (id, slug, name, status, data_region, kms_key_ref, settings, created_at, updated_at) FROM stdin;
3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	enterprise-corp	Enterprise Corporation	active	default	\N	{}	2026-10-06 16:11:03.130751+05:30	2026-10-06 16:11:03.130751+05:30
a3424830-6d45-4ad8-a43b-a5fdf70d691d	acme-corporation-a34248	Acme Corporation	active	us-east-1	\N	{}	2026-10-09 09:52:35.356796+05:30	2026-10-09 09:52:35.356796+05:30
df672f52-b432-45f1-b1a6-4b4b78e23065	apex-technologies-df672f	Apex Technologies	active	us-east-1	\N	{}	2026-10-09 09:52:36.037715+05:30	2026-10-09 09:52:36.037715+05:30
69bb5e9f-858a-4cdc-a6f4-e05b1a80494b	cmp3-69bb5e	cmp3	active	us-east-1	\N	{}	2026-10-09 09:59:27.74813+05:30	2026-10-09 09:59:27.74813+05:30
\.


--
-- Data for Name: user_group_closure; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_group_closure (tenant_id, user_id, group_id, id, depth) FROM stdin;
\.


--
-- Data for Name: user_groups; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_groups (id, tenant_id, name, created_at) FROM stdin;
\.


--
-- Data for Name: user_idp_links; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_idp_links (id, tenant_id, user_id, idp_id, subject) FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, tenant_id, email, display_name, status, clearance_level, attributes, principal_version, last_login_at, created_at, updated_at, password_hash, role, role_key, rank_level, is_active, created_by_id) FROM stdin;
891113ac-2816-4143-ac67-f2e8684d39da	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	hr@enterprise.com	Alice HR Manager	active	3	{"department": "HR"}	1	\N	2026-10-06 16:11:03.176599+05:30	2026-10-06 16:11:03.176599+05:30	\N	employee	employee	5	t	\N
e20419bf-d2fb-46fc-ad10-97a870a8c5f5	3b7e3d55-bfd8-4b7c-b9dd-5509c9ba5e28	employee@enterprise.com	Bob Staff Employee	active	1	{"department": "EMPLOYEE"}	1	\N	2026-10-06 16:11:03.195217+05:30	2026-10-06 16:11:03.195217+05:30	\N	employee	employee	5	t	\N
35217f86-ded0-4e5a-a4f2-cd6bb03c3efa	a3424830-6d45-4ad8-a43b-a5fdf70d691d	admin@acmecorp.com	\N	active	1	{}	1	\N	2026-10-08 16:08:10.293217+05:30	2026-10-08 21:38:10.077416+05:30	$2b$12$qdRlPL0pROyHweJWt.iPKOGbSsGra5yalwLmkng3IB2Wmnlo2tPrC	admin	admin	1	t	61bdc8eb-3dd9-4383-9c10-91bb052e7207
750bfb86-90ed-4754-94fa-abb6ed3713b6	a3424830-6d45-4ad8-a43b-a5fdf70d691d	employee_test@acmecorp.com	\N	active	1	{}	1	\N	2026-10-09 10:54:59.620579+05:30	2026-10-09 10:54:59.620579+05:30	$2b$12$YwNTip6j54PgKrku9Nl0WeLuEv7BD8HvETq95g/hous9Rs4VDXLxm	employee	lead_ai_architect	3	t	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa
e65ce168-7a61-404e-9068-dfb537a03fd0	df672f52-b432-45f1-b1a6-4b4b78e23065	hetvifinance@apex.com	Hetvi Taank	active	1	{}	1	\N	2026-10-10 14:40:17.99593+05:30	2026-10-10 14:40:17.99593+05:30	$2b$12$JSs.e3MRCXIz51zEH9BxpOcZYxm41rP8ULdbjYW9p1iAj15ZPMnxW	employee	finance	2	t	a333efea-a6ac-461f-9639-0a06153c37da
ad5a4022-ce1b-4ce0-8599-af48d160698d	\N	test1@example.com	\N	active	1	{}	1	\N	2026-10-08 20:37:10.315568+05:30	2026-10-08 20:37:10.315568+05:30	$2b$12$yoY8Hbkd9ayTWrFTxsX53uQZjoQFVeAOI62b1kjwCuUknJXkE9t/i	employee	employee	4	t	61bdc8eb-3dd9-4383-9c10-91bb052e7207
fd04d806-81e6-45ac-a9ba-c4e431347c1f	df672f52-b432-45f1-b1a6-4b4b78e23065	trushafin@apex.com	trusha	active	1	{}	1	\N	2026-10-10 14:55:07.505013+05:30	2026-10-10 14:55:07.505013+05:30	$2b$12$HL754oY6BOqZDsxmRy6QguUdtemidB6PrIZcMRu0/vYE6EIZ7TwlC	employee	finance	2	t	a333efea-a6ac-461f-9639-0a06153c37da
82b1aa8b-2641-4866-8792-c5f40e8c468d	\N	test@example.com	\N	active	1	{}	1	\N	2026-10-07 19:00:14.210703+05:30	2026-10-07 19:00:14.210703+05:30	$2b$12$4f7fh7df9B8e4uL01rRC/uzoQBdxh4.0wJbasadTF7rLUavBbHBGS	admin	admin	1	t	\N
9d06613c-0fcd-4a5c-955e-90713bc39693	df672f52-b432-45f1-b1a6-4b4b78e23065	finHetvi@apex.com	Hetvi Taank	active	1	{}	1	\N	2026-10-10 14:49:46.719364+05:30	2026-10-10 14:49:46.719364+05:30	$2b$12$HaA8D.f5L4mpP3eOfeKD6OXKrbmjVnoMYz5IhzHSpmzulYgjKy0ZO	employee	finance	2	t	a333efea-a6ac-461f-9639-0a06153c37da
37c04645-a76d-42d9-9c90-84da82849115	\N	employee@example.com	\N	active	1	{}	1	\N	2026-10-07 18:23:20.322704+05:30	2026-10-07 18:23:20.322704+05:30	$2b$12$oPAOthTi.4yDDWRn21yEne9IhgTzLZgy6mrXj9HmY8D36kfli3d6y	employee	employee	4	t	\N
5b04509c-2d7f-4a1f-8a04-203a1f244904	\N	manager@example.com	\N	active	1	{}	1	\N	2026-10-07 18:23:20.322704+05:30	2026-10-07 18:23:20.322704+05:30	$2b$12$8ZV/hAh.ZxcuJRGjyXfpzucLUgI8D4.j9oqh.PI1/3dul8usYgne.	manager	manager	3	t	\N
61bdc8eb-3dd9-4383-9c10-91bb052e7207	\N	admin@example.com	\N	active	1	{}	1	\N	2026-10-07 18:23:20.322704+05:30	2026-10-07 18:23:20.322704+05:30	$2b$12$T6QbWFuCn1Yp3dHBqWxhU.X79.Kh5kzgRLtwhpf..mB.Q/ECQBWxS	admin	admin	1	t	\N
634ceb49-ffa0-4bac-a523-b45c522f09e4	\N	finance@example.com	\N	active	1	{}	1	\N	2026-10-07 18:23:20.322704+05:30	2026-10-07 18:23:20.322704+05:30	$2b$12$5ZHjmO68oyw0cF2can8OfO2LkHiW3eWlUdIF4834c.Osi4F1dkKUy	finance	finance	2	t	\N
e4130151-2b46-40e5-b604-ed235045a782	69bb5e9f-858a-4cdc-a6f4-e05b1a80494b	cmp3@example.com	\N	active	1	{}	1	\N	2026-10-09 04:29:28.515544+05:30	2026-10-09 09:59:27.74813+05:30	$2b$12$0ifMoqPzqXVjCsuiF8wGuel5O/yzwN.j9x28AxhtnVE67hvqJWh3S	admin	admin	1	t	d943dcaf-f69f-4476-9d47-ed6a852613f5
8fdffb04-e6c2-4c1c-8813-1e9a0767e82e	\N	hr@example.com	\N	active	1	{}	1	\N	2026-10-07 18:23:20.322704+05:30	2026-10-07 18:23:20.322704+05:30	$2b$12$DgEimCVrUF42n6UgXKJKfOsQnZDnRAhQZsD189wvV1qpDBJ11H16K	hr	hr	2	t	\N
d943dcaf-f69f-4476-9d47-ed6a852613f5	\N	system@gmailexample.com	\N	active	1	{}	1	\N	2026-10-08 22:22:42.194874+05:30	2026-10-08 22:22:42.194874+05:30	$2b$12$f/RmFXRKccrJNDJjBbIhhOSl8QTYUlXftEWyT8wXL3nuwMjDt0aq.	admin	system_admin	0	t	\N
995b4d06-051f-48eb-b255-91d7ba54dd18	df672f52-b432-45f1-b1a6-4b4b78e23065	purvahead@apex.com	purva	active	1	{}	1	\N	2026-10-10 15:08:53.188209+05:30	2026-10-10 15:08:53.188209+05:30	$2b$12$ILh8bCxGFqiQZ9CQiSLks.f4BZaebHzuXdFsd/k6g2zNfpBlcI.L.	employee	hr	2	t	a333efea-a6ac-461f-9639-0a06153c37da
2c540497-a8db-40bb-87f7-5ba3641eada7	df672f52-b432-45f1-b1a6-4b4b78e23065	hetvifin1@apex.com	Hetvi Taank	active	1	{}	1	\N	2026-10-10 14:53:27.620355+05:30	2026-10-10 14:53:27.620355+05:30	$2b$12$5lrgneoajaW3i0lg3Z0EeeNGNErpGQcM3uWlRZxaosXz1WFU5Wk2C	employee	finance	2	t	a333efea-a6ac-461f-9639-0a06153c37da
6655cfe1-5ffd-4db2-907d-d2627066a714	a3424830-6d45-4ad8-a43b-a5fdf70d691d	hetvi@admin.com	hetvi	active	1	{}	1	\N	2026-10-10 17:01:50.354852+05:30	2026-10-10 17:01:50.354852+05:30	$2b$12$rJcsLL/dQ9Mi8rJwhPZUYuRa2jTdY751MkytJ780jfLNfDFc4UYDS	employee	finance	2	t	35217f86-ded0-4e5a-a4f2-cd6bb03c3efa
a333efea-a6ac-461f-9639-0a06153c37da	df672f52-b432-45f1-b1a6-4b4b78e23065	admin@apex.com	\N	active	1	{}	1	\N	2026-10-08 17:03:52.678199+05:30	2026-10-08 22:33:52.291871+05:30	$2b$12$ht8m7H2KrrzGyM7B8LUoBexwqErNnMY7JFEYi9kLAmZCDfZbR/jlu	admin	admin	1	t	d943dcaf-f69f-4476-9d47-ed6a852613f5
\.


--
-- Name: acl_outbox_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.acl_outbox_id_seq', 954, true);


--
-- Name: company_roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.company_roles_id_seq', 14, true);


--
-- Name: enterprise_admins_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.enterprise_admins_id_seq', 3, true);


--
-- Name: enterprise_drive_links_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.enterprise_drive_links_id_seq', 1, true);


--
-- Name: feedback_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.feedback_id_seq', 4, true);


--
-- Name: query_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.query_logs_id_seq', 8, true);


--
-- Name: sources_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.sources_id_seq', 1, false);


--
-- Name: team_chat_messages_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.team_chat_messages_id_seq', 1, false);


--
-- Name: team_members_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.team_members_id_seq', 1, false);


--
-- Name: teams_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.teams_id_seq', 1, false);


--
-- Name: user_group_closure_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_group_closure_id_seq', 1, false);


--
-- Name: abac_policies abac_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.abac_policies
    ADD CONSTRAINT abac_policies_pkey PRIMARY KEY (id);


--
-- Name: abac_policies abac_policies_tenant_id_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.abac_policies
    ADD CONSTRAINT abac_policies_tenant_id_name_key UNIQUE (tenant_id, name);


--
-- Name: acl_outbox acl_outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.acl_outbox
    ADD CONSTRAINT acl_outbox_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id, occurred_at);


--
-- Name: audit_logs_default audit_logs_default_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs_default
    ADD CONSTRAINT audit_logs_default_pkey PRIMARY KEY (id, occurred_at);


--
-- Name: chunks chunks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chunks
    ADD CONSTRAINT chunks_pkey PRIMARY KEY (id);


--
-- Name: classification_levels classification_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.classification_levels
    ADD CONSTRAINT classification_levels_pkey PRIMARY KEY (tenant_id, level);


--
-- Name: company_roles company_roles_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_roles
    ADD CONSTRAINT company_roles_key_key UNIQUE (key);


--
-- Name: company_roles company_roles_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_roles
    ADD CONSTRAINT company_roles_name_key UNIQUE (name);


--
-- Name: company_roles company_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_roles
    ADD CONSTRAINT company_roles_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: document_acl_entries document_acl_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_acl_entries
    ADD CONSTRAINT document_acl_entries_pkey PRIMARY KEY (id);


--
-- Name: document_versions document_versions_document_id_version_no_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_versions
    ADD CONSTRAINT document_versions_document_id_version_no_key UNIQUE (document_id, version_no);


--
-- Name: document_versions document_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_versions
    ADD CONSTRAINT document_versions_pkey PRIMARY KEY (id);


--
-- Name: document_versions document_versions_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_versions
    ADD CONSTRAINT document_versions_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: enterprise_admins enterprise_admins_admin_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enterprise_admins
    ADD CONSTRAINT enterprise_admins_admin_email_key UNIQUE (admin_email);


--
-- Name: enterprise_admins enterprise_admins_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enterprise_admins
    ADD CONSTRAINT enterprise_admins_pkey PRIMARY KEY (id);


--
-- Name: enterprise_drive_links enterprise_drive_links_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enterprise_drive_links
    ADD CONSTRAINT enterprise_drive_links_pkey PRIMARY KEY (id);


--
-- Name: external_identities external_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.external_identities
    ADD CONSTRAINT external_identities_pkey PRIMARY KEY (id);


--
-- Name: external_identities external_identities_tenant_id_source_type_external_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.external_identities
    ADD CONSTRAINT external_identities_tenant_id_source_type_external_id_key UNIQUE (tenant_id, source_type, external_id);


--
-- Name: feedback feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_pkey PRIMARY KEY (id);


--
-- Name: group_members group_members_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT group_members_pkey PRIMARY KEY (id);


--
-- Name: groups groups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (id);


--
-- Name: groups groups_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: identity_providers identity_providers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.identity_providers
    ADD CONSTRAINT identity_providers_pkey PRIMARY KEY (id);


--
-- Name: identity_providers identity_providers_tenant_id_issuer_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.identity_providers
    ADD CONSTRAINT identity_providers_tenant_id_issuer_key UNIQUE (tenant_id, issuer);


--
-- Name: ingestion_jobs ingestion_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ingestion_jobs
    ADD CONSTRAINT ingestion_jobs_pkey PRIMARY KEY (id);


--
-- Name: message_citations message_citations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.message_citations
    ADD CONSTRAINT message_citations_pkey PRIMARY KEY (id);


--
-- Name: message_feedback message_feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.message_feedback
    ADD CONSTRAINT message_feedback_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: messages messages_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (code);


--
-- Name: pii_findings pii_findings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pii_findings
    ADD CONSTRAINT pii_findings_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: projects projects_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: projects projects_tenant_id_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_tenant_id_key_key UNIQUE (tenant_id, key);


--
-- Name: query_logs query_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.query_logs
    ADD CONSTRAINT query_logs_pkey PRIMARY KEY (id);


--
-- Name: retrieval_events retrieval_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.retrieval_events
    ADD CONSTRAINT retrieval_events_pkey PRIMARY KEY (id);


--
-- Name: role_assignments role_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT role_assignments_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: roles roles_tenant_id_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_tenant_id_name_key UNIQUE (tenant_id, name);


--
-- Name: source_connections source_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.source_connections
    ADD CONSTRAINT source_connections_pkey PRIMARY KEY (id);


--
-- Name: source_connections source_connections_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.source_connections
    ADD CONSTRAINT source_connections_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: source_connections source_connections_tenant_id_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.source_connections
    ADD CONSTRAINT source_connections_tenant_id_name_key UNIQUE (tenant_id, name);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (id);


--
-- Name: sources sources_uri_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_uri_key UNIQUE (uri);


--
-- Name: sync_runs sync_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_runs
    ADD CONSTRAINT sync_runs_pkey PRIMARY KEY (id);


--
-- Name: system_settings system_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_pkey PRIMARY KEY (key);


--
-- Name: team_chat_messages team_chat_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team_chat_messages
    ADD CONSTRAINT team_chat_messages_pkey PRIMARY KEY (id);


--
-- Name: team_members team_members_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_pkey PRIMARY KEY (id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: tenants tenants_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_slug_key UNIQUE (slug);


--
-- Name: user_group_closure user_group_closure_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_group_closure
    ADD CONSTRAINT user_group_closure_pkey PRIMARY KEY (tenant_id, user_id, group_id);


--
-- Name: user_groups user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_groups
    ADD CONSTRAINT user_groups_pkey PRIMARY KEY (id);


--
-- Name: user_idp_links user_idp_links_idp_id_subject_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_idp_links
    ADD CONSTRAINT user_idp_links_idp_id_subject_key UNIQUE (idp_id, subject);


--
-- Name: user_idp_links user_idp_links_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_idp_links
    ADD CONSTRAINT user_idp_links_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_tenant_id_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_tenant_id_email_key UNIQUE (tenant_id, email);


--
-- Name: users users_tenant_id_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_tenant_id_id_key UNIQUE (tenant_id, id);


--
-- Name: ix_audit_actor; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_audit_actor ON ONLY public.audit_logs USING btree (tenant_id, actor_user_id, occurred_at DESC);


--
-- Name: audit_logs_default_tenant_id_actor_user_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX audit_logs_default_tenant_id_actor_user_id_occurred_at_idx ON public.audit_logs_default USING btree (tenant_id, actor_user_id, occurred_at DESC);


--
-- Name: ix_audit_tenant_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_audit_tenant_time ON ONLY public.audit_logs USING btree (tenant_id, occurred_at DESC);


--
-- Name: audit_logs_default_tenant_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX audit_logs_default_tenant_id_occurred_at_idx ON public.audit_logs_default USING btree (tenant_id, occurred_at DESC);


--
-- Name: idx_acl_document; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_acl_document ON public.document_acl_entries USING btree (document_id);


--
-- Name: idx_chunks_doc_chunk; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chunks_doc_chunk ON public.chunks USING btree (document_id, chunk_index);


--
-- Name: idx_doc_versions_doc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_doc_versions_doc ON public.document_versions USING btree (document_id, is_current);


--
-- Name: idx_users_tenant_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_tenant_email ON public.users USING btree (tenant_id, email);


--
-- Name: ix_acl_doc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_acl_doc ON public.document_acl_entries USING btree (tenant_id, document_id);


--
-- Name: ix_acl_outbox_pending; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_acl_outbox_pending ON public.acl_outbox USING btree (created_at) WHERE (status = 'pending'::text);


--
-- Name: ix_chunks_document_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_chunks_document_id ON public.chunks USING btree (document_id);


--
-- Name: ix_conv_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_conv_user ON public.conversations USING btree (tenant_id, user_id, updated_at DESC);


--
-- Name: ix_documents_source_hash; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_documents_source_hash ON public.documents USING btree (source_hash);


--
-- Name: ix_jobs_version; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_jobs_version ON public.ingestion_jobs USING btree (tenant_id, document_version_id);


--
-- Name: ix_msg_conv; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_msg_conv ON public.messages USING btree (tenant_id, conversation_id, created_at);


--
-- Name: ix_ra_group; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ra_group ON public.role_assignments USING btree (tenant_id, group_id) WHERE (group_id IS NOT NULL);


--
-- Name: ix_ra_project; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ra_project ON public.role_assignments USING btree (tenant_id, project_id);


--
-- Name: ix_ra_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_ra_user ON public.role_assignments USING btree (tenant_id, user_id) WHERE (user_id IS NOT NULL);


--
-- Name: ix_retr_tenant_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_retr_tenant_time ON public.retrieval_events USING btree (tenant_id, created_at DESC);


--
-- Name: uq_acl_entry; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_acl_entry ON public.document_acl_entries USING btree (document_id, principal_type, COALESCE(principal_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(external_ref, ''::text), effect, permission);


--
-- Name: uq_gm_group; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_gm_group ON public.group_members USING btree (group_id, member_group_id) WHERE (member_group_id IS NOT NULL);


--
-- Name: uq_gm_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_gm_user ON public.group_members USING btree (group_id, member_user_id) WHERE (member_user_id IS NOT NULL);


--
-- Name: uq_groups_external; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_groups_external ON public.groups USING btree (tenant_id, origin, COALESCE(source_connection_id, '00000000-0000-0000-0000-000000000000'::uuid), external_ref) WHERE (external_ref IS NOT NULL);


--
-- Name: uq_one_current_version; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_one_current_version ON public.document_versions USING btree (document_id) WHERE is_current;


--
-- Name: uq_roles_system_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_roles_system_name ON public.roles USING btree (name) WHERE (tenant_id IS NULL);


--
-- Name: audit_logs_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.audit_logs_pkey ATTACH PARTITION public.audit_logs_default_pkey;


--
-- Name: audit_logs_default_tenant_id_actor_user_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.ix_audit_actor ATTACH PARTITION public.audit_logs_default_tenant_id_actor_user_id_occurred_at_idx;


--
-- Name: audit_logs_default_tenant_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.ix_audit_tenant_time ATTACH PARTITION public.audit_logs_default_tenant_id_occurred_at_idx;


--
-- Name: abac_policies abac_policies_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.abac_policies
    ADD CONSTRAINT abac_policies_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: chunks chunks_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chunks
    ADD CONSTRAINT chunks_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE CASCADE;


--
-- Name: classification_levels classification_levels_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.classification_levels
    ADD CONSTRAINT classification_levels_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: conversations conversations_tenant_id_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_tenant_id_project_id_fkey FOREIGN KEY (tenant_id, project_id) REFERENCES public.projects(tenant_id, id);


--
-- Name: conversations conversations_tenant_id_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_tenant_id_user_id_fkey FOREIGN KEY (tenant_id, user_id) REFERENCES public.users(tenant_id, id);


--
-- Name: document_versions document_versions_tenant_id_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_versions
    ADD CONSTRAINT document_versions_tenant_id_approved_by_fkey FOREIGN KEY (tenant_id, approved_by) REFERENCES public.users(tenant_id, id);


--
-- Name: enterprise_admins enterprise_admins_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enterprise_admins
    ADD CONSTRAINT enterprise_admins_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: external_identities external_identities_tenant_id_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.external_identities
    ADD CONSTRAINT external_identities_tenant_id_user_id_fkey FOREIGN KEY (tenant_id, user_id) REFERENCES public.users(tenant_id, id) ON DELETE CASCADE;


--
-- Name: feedback feedback_query_log_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_query_log_id_fkey FOREIGN KEY (query_log_id) REFERENCES public.query_logs(id) ON DELETE CASCADE;


--
-- Name: group_members group_members_tenant_id_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT group_members_tenant_id_group_id_fkey FOREIGN KEY (tenant_id, group_id) REFERENCES public.groups(tenant_id, id) ON DELETE CASCADE;


--
-- Name: group_members group_members_tenant_id_member_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT group_members_tenant_id_member_group_id_fkey FOREIGN KEY (tenant_id, member_group_id) REFERENCES public.groups(tenant_id, id) ON DELETE CASCADE;


--
-- Name: group_members group_members_tenant_id_member_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT group_members_tenant_id_member_user_id_fkey FOREIGN KEY (tenant_id, member_user_id) REFERENCES public.users(tenant_id, id) ON DELETE CASCADE;


--
-- Name: groups groups_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: groups groups_tenant_id_source_connection_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_tenant_id_source_connection_id_fkey FOREIGN KEY (tenant_id, source_connection_id) REFERENCES public.source_connections(tenant_id, id) ON DELETE CASCADE;


--
-- Name: identity_providers identity_providers_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.identity_providers
    ADD CONSTRAINT identity_providers_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: message_citations message_citations_tenant_id_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.message_citations
    ADD CONSTRAINT message_citations_tenant_id_message_id_fkey FOREIGN KEY (tenant_id, message_id) REFERENCES public.messages(tenant_id, id) ON DELETE CASCADE;


--
-- Name: message_feedback message_feedback_tenant_id_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.message_feedback
    ADD CONSTRAINT message_feedback_tenant_id_message_id_fkey FOREIGN KEY (tenant_id, message_id) REFERENCES public.messages(tenant_id, id) ON DELETE CASCADE;


--
-- Name: message_feedback message_feedback_tenant_id_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.message_feedback
    ADD CONSTRAINT message_feedback_tenant_id_user_id_fkey FOREIGN KEY (tenant_id, user_id) REFERENCES public.users(tenant_id, id);


--
-- Name: messages messages_tenant_id_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_tenant_id_conversation_id_fkey FOREIGN KEY (tenant_id, conversation_id) REFERENCES public.conversations(tenant_id, id) ON DELETE CASCADE;


--
-- Name: projects projects_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: projects projects_tenant_id_owner_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_tenant_id_owner_user_id_fkey FOREIGN KEY (tenant_id, owner_user_id) REFERENCES public.users(tenant_id, id);


--
-- Name: role_assignments role_assignments_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT role_assignments_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- Name: role_assignments role_assignments_tenant_id_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT role_assignments_tenant_id_group_id_fkey FOREIGN KEY (tenant_id, group_id) REFERENCES public.groups(tenant_id, id) ON DELETE CASCADE;


--
-- Name: role_assignments role_assignments_tenant_id_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT role_assignments_tenant_id_project_id_fkey FOREIGN KEY (tenant_id, project_id) REFERENCES public.projects(tenant_id, id) ON DELETE CASCADE;


--
-- Name: role_assignments role_assignments_tenant_id_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT role_assignments_tenant_id_user_id_fkey FOREIGN KEY (tenant_id, user_id) REFERENCES public.users(tenant_id, id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_permission_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_permission_fkey FOREIGN KEY (permission) REFERENCES public.permissions(code);


--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: roles roles_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: source_connections source_connections_tenant_id_default_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.source_connections
    ADD CONSTRAINT source_connections_tenant_id_default_project_id_fkey FOREIGN KEY (tenant_id, default_project_id) REFERENCES public.projects(tenant_id, id);


--
-- Name: source_connections source_connections_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.source_connections
    ADD CONSTRAINT source_connections_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: sync_runs sync_runs_tenant_id_source_connection_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_runs
    ADD CONSTRAINT sync_runs_tenant_id_source_connection_id_fkey FOREIGN KEY (tenant_id, source_connection_id) REFERENCES public.source_connections(tenant_id, id) ON DELETE CASCADE;


--
-- Name: team_chat_messages team_chat_messages_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team_chat_messages
    ADD CONSTRAINT team_chat_messages_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: team_members team_members_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: team_members team_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_group_closure user_group_closure_tenant_id_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_group_closure
    ADD CONSTRAINT user_group_closure_tenant_id_group_id_fkey FOREIGN KEY (tenant_id, group_id) REFERENCES public.groups(tenant_id, id) ON DELETE CASCADE;


--
-- Name: user_group_closure user_group_closure_tenant_id_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_group_closure
    ADD CONSTRAINT user_group_closure_tenant_id_user_id_fkey FOREIGN KEY (tenant_id, user_id) REFERENCES public.users(tenant_id, id) ON DELETE CASCADE;


--
-- Name: user_idp_links user_idp_links_idp_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_idp_links
    ADD CONSTRAINT user_idp_links_idp_id_fkey FOREIGN KEY (idp_id) REFERENCES public.identity_providers(id);


--
-- Name: user_idp_links user_idp_links_tenant_id_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_idp_links
    ADD CONSTRAINT user_idp_links_tenant_id_user_id_fkey FOREIGN KEY (tenant_id, user_id) REFERENCES public.users(tenant_id, id) ON DELETE CASCADE;


--
-- Name: users users_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: abac_policies; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.abac_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: acl_outbox; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.acl_outbox ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs audit_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY audit_insert ON public.audit_logs FOR INSERT WITH CHECK (((tenant_id IS NULL) OR (tenant_id = app.current_tenant())));


--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs audit_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY audit_read ON public.audit_logs FOR SELECT USING ((tenant_id = app.current_tenant()));


--
-- Name: classification_levels; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.classification_levels ENABLE ROW LEVEL SECURITY;

--
-- Name: conversations; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: document_acl_entries; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.document_acl_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: document_versions; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.document_versions ENABLE ROW LEVEL SECURITY;

--
-- Name: external_identities; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.external_identities ENABLE ROW LEVEL SECURITY;

--
-- Name: group_members; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

--
-- Name: groups; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

--
-- Name: identity_providers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.identity_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: ingestion_jobs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.ingestion_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: message_citations; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.message_citations ENABLE ROW LEVEL SECURITY;

--
-- Name: message_feedback; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.message_feedback ENABLE ROW LEVEL SECURITY;

--
-- Name: messages; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: pii_findings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.pii_findings ENABLE ROW LEVEL SECURITY;

--
-- Name: projects; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

--
-- Name: retrieval_events; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.retrieval_events ENABLE ROW LEVEL SECURITY;

--
-- Name: role_assignments; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.role_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: roles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

--
-- Name: roles roles_visible; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY roles_visible ON public.roles FOR SELECT USING (((tenant_id IS NULL) OR (tenant_id = app.current_tenant())));


--
-- Name: roles roles_write; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY roles_write ON public.roles USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: source_connections; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.source_connections ENABLE ROW LEVEL SECURITY;

--
-- Name: sync_runs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sync_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: abac_policies tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.abac_policies USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: acl_outbox tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.acl_outbox USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: classification_levels tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.classification_levels USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: conversations tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.conversations USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: document_acl_entries tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.document_acl_entries USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: document_versions tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.document_versions USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: external_identities tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.external_identities USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: group_members tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.group_members USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: groups tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.groups USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: identity_providers tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.identity_providers USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: ingestion_jobs tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.ingestion_jobs USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: message_citations tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.message_citations USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: message_feedback tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.message_feedback USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: messages tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.messages USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: pii_findings tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.pii_findings USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: projects tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.projects USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: retrieval_events tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.retrieval_events USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: role_assignments tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.role_assignments USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: source_connections tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.source_connections USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: sync_runs tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.sync_runs USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: user_group_closure tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.user_group_closure USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: user_idp_links tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.user_idp_links USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: users tenant_isolation; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_isolation ON public.users USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


--
-- Name: tenants tenant_self; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY tenant_self ON public.tenants USING ((id = app.current_tenant()));


--
-- Name: tenants; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

--
-- Name: user_group_closure; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_group_closure ENABLE ROW LEVEL SECURITY;

--
-- Name: user_idp_links; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_idp_links ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict srmyfiULak6NoKv9McAc2AvVO0enKIhfF7qvlsGXcMvFpuwqFlYoIQfodIXJ34e

