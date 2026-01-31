import { writable } from 'svelte/store';

interface UIState {
  sidebarOpen: boolean;
  theme: 'light' | 'dark';
}

const initialState: UIState = {
  sidebarOpen: true,
  theme: 'light',
};

export const uiStore = writable<UIState>(initialState);

export function toggleSidebar() {
  uiStore.update((state) => ({ ...state, sidebarOpen: !state.sidebarOpen }));
}

export function setTheme(theme: 'light' | 'dark') {
  uiStore.update((state) => ({ ...state, theme }));
}
