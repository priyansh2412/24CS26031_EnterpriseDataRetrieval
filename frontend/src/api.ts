const API = import.meta.env.VITE_API_URL || "http://localhost:8000";

export const token = () => localStorage.getItem("rag_token");

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
  id: number;
  email: string;
  role: string;
  role_key?: string;
  rank_level: number;
  is_active: boolean;
}

export interface AuditLogItem {
  id: number;
  user_id: number | null;
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
  id: number;
  email: string;
  role_key: string;
  rank_level: number;
}

export interface TeamMemberItem {
  id: number;
  user_id: number;
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
  created_by_id: number;
  created_at: string;
  members: TeamMemberItem[];
}

export interface TeamChatMessageItem {
  id: number;
  team_id: number;
  user_id: number;
  user_email: string;
  message: string;
  response: string;
  citations: Array<{ document_id: number; document_name: string; chunk_index: number; text: string; score: number }>;
  created_at: string;
}

export async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string> || {}),
  };
  
  const currentToken = token();
  if (currentToken) {
    headers["Authorization"] = `Bearer ${currentToken}`;
  }

  let response: Response;
  try {
    response = await fetch(`${API}${path}`, {
      ...options,
      headers,
    });
  } catch (err) {
    throw new Error(`Unable to connect to backend server at ${API}. Please ensure the backend server is running.`);
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
  
  let response: Response;
  try {
    response = await fetch(`${API}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });
  } catch (err) {
    throw new Error(`Cannot connect to authentication service at ${API}. Check backend server.`);
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

