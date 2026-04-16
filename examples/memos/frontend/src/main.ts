import './style.css';
import { setToken, clearToken, isLoggedIn } from './auth';
import {
  register,
  login,
  listMemos,
  createMemo,
  updateMemo,
  deleteMemo,
} from './api';

const app = document.querySelector<HTMLDivElement>('#app')!;

function renderAuth() {
  app.innerHTML = `
    <h1>Memos</h1>
    <div class="card">
      <h3>Login</h3>
      <input id="lu" placeholder="Username" />
      <input id="lp" type="password" placeholder="Password" style="margin-top:0.5rem" />
      <div class="actions">
        <button id="btn-login">Login</button>
        <button class="secondary" id="btn-to-register">Register</button>
      </div>
      <div class="error" id="auth-err"></div>
    </div>
  `;

  const errEl = document.getElementById('auth-err')!;

  document.getElementById('btn-login')!.onclick = async () => {
    errEl.textContent = '';
    try {
      const res = await login(
        (document.getElementById('lu') as HTMLInputElement).value,
        (document.getElementById('lp') as HTMLInputElement).value
      );
      setToken(res.token);
      renderApp();
    } catch (e: any) {
      errEl.textContent = e.message || 'Login failed';
    }
  };

  document.getElementById('btn-to-register')!.onclick = () => renderRegister();
}

function renderRegister() {
  app.innerHTML = `
    <h1>Memos</h1>
    <div class="card">
      <h3>Register</h3>
      <input id="ru" placeholder="Username" />
      <input id="rp" type="password" placeholder="Password" style="margin-top:0.5rem" />
      <div class="actions">
        <button id="btn-register">Register</button>
        <button class="secondary" id="btn-to-login">Back to Login</button>
      </div>
      <div class="error" id="auth-err"></div>
    </div>
  `;

  const errEl = document.getElementById('auth-err')!;

  document.getElementById('btn-register')!.onclick = async () => {
    errEl.textContent = '';
    try {
      await register(
        (document.getElementById('ru') as HTMLInputElement).value,
        (document.getElementById('rp') as HTMLInputElement).value
      );
      renderAuth();
    } catch (e: any) {
      errEl.textContent = e.message || 'Register failed';
    }
  };

  document.getElementById('btn-to-login')!.onclick = () => renderAuth();
}

async function renderApp() {
  app.innerHTML = `
    <div class="header">
      <h1>Memos</h1>
      <button class="secondary" id="btn-logout">Logout</button>
    </div>
    <div class="card">
      <textarea id="new-content" placeholder="Write a memo..."></textarea>
      <div class="actions">
        <button id="btn-add">Add Memo</button>
      </div>
      <div class="error" id="add-err"></div>
    </div>
    <div id="memos"></div>
  `;

  document.getElementById('btn-logout')!.onclick = () => {
    clearToken();
    renderAuth();
  };

  document.getElementById('btn-add')!.onclick = async () => {
    const el = document.getElementById('new-content') as HTMLTextAreaElement;
    const errEl = document.getElementById('add-err')!;
    errEl.textContent = '';
    try {
      await createMemo(el.value);
      el.value = '';
      await loadMemos();
    } catch (e: any) {
      errEl.textContent = e.message || 'Failed to add memo';
    }
  };

  await loadMemos();
}

async function loadMemos() {
  const container = document.getElementById('memos')!;
  try {
    const memos = await listMemos();
    container.innerHTML = memos.length
      ? memos
          .map(
            (m) => `
        <div class="card" data-id="${m.id}">
          <div class="memo-content">${escapeHtml(m.content)}</div>
          <div class="memo-time">${new Date(m.updated_at).toLocaleString()}</div>
          <div class="actions">
            <button class="secondary btn-edit">Edit</button>
            <button class="danger btn-delete">Delete</button>
          </div>
        </div>
      `
          )
          .join('')
      : '<p>No memos yet.</p>';

    container.querySelectorAll('.btn-edit').forEach((btn) => {
      btn.addEventListener('click', () => {
        const card = (btn as HTMLElement).closest('.card')!;
        const id = Number(card.getAttribute('data-id'));
        const content = card.querySelector('.memo-content')!.textContent || '';
        startEdit(card as HTMLElement, id, content);
      });
    });

    container.querySelectorAll('.btn-delete').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const card = (btn as HTMLElement).closest('.card')!;
        const id = Number(card.getAttribute('data-id'));
        if (!confirm('Delete this memo?')) return;
        try {
          await deleteMemo(id);
          await loadMemos();
        } catch {}
      });
    });
  } catch {
    container.innerHTML = '<p class="error">Failed to load memos.</p>';
  }
}

function startEdit(card: HTMLElement, id: number, content: string) {
  card.innerHTML = `
    <textarea class="edit-content">${escapeHtml(content)}</textarea>
    <div class="actions">
      <button class="btn-save">Save</button>
      <button class="secondary btn-cancel">Cancel</button>
    </div>
    <div class="error edit-err"></div>
  `;

  card.querySelector('.btn-cancel')!.addEventListener('click', () => loadMemos());

  card.querySelector('.btn-save')!.addEventListener('click', async () => {
    const val = (card.querySelector('.edit-content') as HTMLTextAreaElement).value;
    const errEl = card.querySelector('.edit-err')!;
    errEl.textContent = '';
    try {
      await updateMemo(id, val);
      await loadMemos();
    } catch (e: any) {
      errEl.textContent = e.message || 'Failed to save';
    }
  });
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

if (isLoggedIn()) {
  renderApp();
} else {
  renderAuth();
}
