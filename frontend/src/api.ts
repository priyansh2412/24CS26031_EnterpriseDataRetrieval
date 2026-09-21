const API = import.meta.env.VITE_API_URL || "http://localhost:8000";

export const token = () => localStorage.getItem("rag_token");

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
