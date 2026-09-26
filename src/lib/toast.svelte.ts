export type ToastKind = 'info' | 'success' | 'error';

export interface Toast {
  id: number;
  kind: ToastKind;
  text: string;
}

export const toasts: Toast[] = $state([]);
let next = 0;

export function dismiss(id: number) {
  const i = toasts.findIndex((t) => t.id === id);
  if (i >= 0) toasts.splice(i, 1);
}

export function toast(text: string, kind: ToastKind = 'info', ms = kind === 'error' ? 8000 : 4000) {
  const id = ++next;
  toasts.push({ id, kind, text });
  setTimeout(() => dismiss(id), ms);
}
