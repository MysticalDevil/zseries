import { getToken } from './auth';

const API_BASE = 'http://localhost:8082/api';

async function fetchJson<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...((options.headers as Record<string, string>) || {}),
  };
  const token = getToken();
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers,
    credentials: 'include',
  });

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `HTTP ${res.status}`);
  }

  if (res.status === 204) {
    return undefined as unknown as T;
  }

  const text = await res.text();
  return text ? (JSON.parse(text) as T) : (undefined as unknown as T);
}

export interface Memo {
  id: number;
  content: string;
  updated_at: number;
}

export function register(username: string, password: string) {
  return fetchJson<{ id: number; username: string }>('/auth/register', {
    method: 'POST',
    body: JSON.stringify({ username, password }),
  });
}

export function login(username: string, password: string) {
  return fetchJson<{ token: string }>('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ username, password }),
  });
}

export function listMemos() {
  return fetchJson<Memo[]>('/memos', { method: 'GET' });
}

export function createMemo(content: string) {
  return fetchJson<{ id: number; content: string }>('/memos', {
    method: 'POST',
    body: JSON.stringify({ content }),
  });
}

export function updateMemo(id: number, content: string) {
  return fetchJson<{ id: number; content: string }>(`/memos/${id}`, {
    method: 'PUT',
    body: JSON.stringify({ content }),
  });
}

export function deleteMemo(id: number) {
  return fetchJson<void>(`/memos/${id}`, { method: 'DELETE' });
}
