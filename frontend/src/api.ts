export interface CompanyRoleItem {
  id?: number;
  name: string;
  key: string;
  rank_level: number;
  description?: string;
  permissions?: string[];
}

export interface SetupStatus {
  is_initialized: boolean;
  company_name?: string;
}

export interface SystemSetupPayload {
  company_name: string;
  roles: CompanyRoleItem[];
  admin_email: string;
  admin_password: string;
}

export interface UserProfile {
  id: string | number;
  email: string;
  display_name?: string;
  role: string;
  role_key?: string;
  rank_level: number;
  is_active: boolean;
  tenant_id?: string;
  enterprise_name?: string;
  created_at?: string;
}

export interface UserItem {
  id: string | number;
  email: string;
  display_name?: string;
  role: string;
  role_key?: string;
  rank_level: number;
  is_active: boolean;
  tenant_id?: string;
  created_at?: string;
}

export interface AuditLogItem {
  id: string | number;
  user_id: string | number | null;
  user_email: string | null;
  user_role_key: string | null;
  user_rank_level: number | null;
  action: string;
  resource_type: string;
  resource_id: string | null;
  severity: "INFO" | "WARNING" | "ERROR" | "CRITICAL";
  detail: string | null;
  created_at: string;
}

export interface SubordinateUserItem {
  id: string | number;
  email: string;
  role_key: string;
  rank_level: number;
}

export interface TeamMemberItem {
  id: number;
  user_id: string | number;
  user_email: string;
  user_role_key?: string;
  user_rank_level?: number;
  role_in_team: string;
}

export interface TeamItem {
  id: number;
  name: string;
  project_name: string;
  description?: string;
  created_by_id: string | number;
  created_at: string;
  members: TeamMemberItem[];
}

export interface TeamChatMessageItem {
  id: number;
  team_id: number;
  user_id: string | number;
  user_email: string;
  message: string;
  response: string;
  citations: Array<{ document_id: string | number; document_name: string; chunk_index: number; text: string; score: number }>;
  created_at: string;
}

export interface EnterpriseItem {
  id: number;
  enterprise_name: string;
  admin_email: string;
  temp_password: string;
  user_id?: string | number | null;
  tenant_id: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface EnterpriseCreatePayload {
  enterprise_name: string;
  admin_email: string;
  temp_password?: string;
  tenant_id?: string;
}

export interface EnterpriseDriveLinkItem {
  id: number;
  tenant_id: string;
  name: string;
  drive_url: string;
  drive_id?: string;
  is_folder: boolean;
  is_password_protected: boolean;
  status: string;
  doc_count: number;
  created_at: string;
  updated_at: string;
}

export interface DocumentItem {
  id: string;
  name: string;
  source: string;
  status: string;
  chunk_count: number;
  access_roles?: string;
  denied_users?: string;
  folder_path?: string;
  drive_link_id?: number | null;
  summary?: string;
  created_at: string;
}

const PRIMARY_API = import.meta.env.VITE_API_URL || "http://127.0.0.1:8000";
const FALLBACK_API = "http://127.0.0.1:8001";
let activeApi = PRIMARY_API;

export const token = () => localStorage.getItem("rag_token");

export interface TempDocItem {
  document_id: string;
  name: string;
  chunk_count: number;
  size_bytes?: number;
  created_at?: string;
  status?: string;
}

export async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const isFormData = typeof FormData !== "undefined" && options.body instanceof FormData;
  const headers: Record<string, string> = {
    ...(!isFormData ? { "Content-Type": "application/json" } : {}),
    ...((options.headers as Record<string, string>) || {}),
  };
  
  const currentToken = token();
  if (currentToken) {
    headers["Authorization"] = `Bearer ${currentToken}`;
  }

  let response: Response | null = null;
  const targets = [PRIMARY_API, FALLBACK_API];

  for (const target of targets) {
    try {
      const res = await fetch(`${target}${path}`, {
        ...options,
        headers,
      });
      response = res;
      activeApi = target;
      break;
    } catch {
      // try fallback port
    }
  }

  if (!response) {
    activeApi = PRIMARY_API;
    throw new Error(`Unable to connect to backend server at ${PRIMARY_API}. Please ensure the backend server is running.`);
  }

  if (!response.ok) {
    const errorBody = await response.json().catch(() => ({ detail: "Request failed" }));
    throw new Error(errorBody.detail || "Request failed");
  }

  return response.status === 204 ? (undefined as T) : response.json();
}

export async function login(email: string, password: string): Promise<void> {
  const cleanEmail = email.trim();
  const body = new URLSearchParams({ username: cleanEmail, password });
  
  let response: Response | null = null;
  const targets = [activeApi, activeApi === PRIMARY_API ? FALLBACK_API : PRIMARY_API];

  for (const target of targets) {
    try {
      response = await fetch(`${target}/api/auth/login`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body,
      });
      activeApi = target;
      break;
    } catch {
      // try fallback port
    }
  }

  if (!response) {
    throw new Error(`Cannot connect to authentication service at ${activeApi}. Check backend server.`);
  }

  if (!response.ok) {
    const err = await response.json().catch(() => ({ detail: "Login failed" }));
    throw new Error(err.detail || "Login failed. Incorrect email or password.");
  }

  const data = await response.json();
  localStorage.setItem("rag_token", data.access_token);
}

export async function forgotPassword(email: string): Promise<{ message: string }> {
  return request<{ message: string }>("/api/auth/forgot-password", {
    method: "POST",
    body: JSON.stringify({ email: email.trim() }),
  });
}

