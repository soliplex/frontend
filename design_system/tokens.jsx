/* Shared Soliplex tokens + inlined component primitives used by all three
   mockups (lobby, room, quiz). Exposes them on window so each scene file
   can pull what it needs without cross-script imports. */

const SP_LIGHT = {
  background:'#ffffff', foreground:'#0A0A0A',
  primary:'#030213', onPrimary:'#ffffff',
  primaryContainer:'#E0DDDA', onPrimaryContainer:'#0A0A0A',
  secondary:'#F3F3FA', tertiary:'#6B7280',
  accent:'#E9EBEF', muted:'#ECECF0', mutedFg:'#595968',
  destructive:'#D4183D', errorContainer:'#FEE2E2', onErrorContainer:'#991B1B',
  successContainer:'#DCFCE7', onSuccessContainer:'#166534',
  border:'rgba(0,0,0,0.10)', outline:'#C0C0C4', outlineVariant:'#E0E0E2',
  inputBg:'#F3F3F5', hint:'#666666',
  surfaceLow:'#EFEFEF', surfaceHigh:'#ECECEC', surfaceHighest:'#E4E4E4',
  link:'#2563EB',
};

const SP_DARK = {
  background:'#111111', foreground:'#FAFAFA',
  primary:'#FAFAFA', onPrimary:'#222222',
  primaryContainer:'#2A2A2A', onPrimaryContainer:'#FAFAFA',
  secondary:'#2A2A2A', tertiary:'#9CA3AF',
  accent:'#2A2A2A', muted:'#444444', mutedFg:'#AAAAAA',
  destructive:'#D4183D', errorContainer:'#3D1A1A', onErrorContainer:'#FCA5A5',
  successContainer:'#1A3D1A', onSuccessContainer:'#86EFAC',
  border:'#2A2A2A', outline:'#555555', outlineVariant:'#3A3A3A',
  inputBg:'#333333', hint:'#A3A3A3',
  surfaceLow:'#1A1A1A', surfaceHigh:'#2A2A2A', surfaceHighest:'#333333',
  link:'#60A5FA',
};

const SP_FONT = 'system-ui, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif';
const SP_MONO = '"JetBrains Mono", "SF Mono", "Roboto Mono", ui-monospace, Menlo, Consolas, monospace';

function Icon({ d, size = 20, stroke = 'currentColor', fill = 'none', sw = 2 }) {
  const paths = Array.isArray(d) ? d : [d];
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke={stroke}
      strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
      {paths.map((p, i) => <path key={i} d={p} />)}
    </svg>
  );
}

const ICON = {
  search: 'M21 21l-4.3-4.3 M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14',
  plus: 'M12 5v14 M5 12h14',
  info: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20 M12 16v-4 M12 8h.01',
  close: 'M6 6l12 12 M18 6L6 18',
  send: 'M22 2L11 13 M22 2l-7 20-4-9-9-4 20-7',
  lock: 'M5 11h14v10H5z M7 11V7a5 5 0 0 1 10 0v4',
  doc: 'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6',
  attach: 'M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48',
  quiz: 'M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3 M12 17h.01 M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20',
  bolt: 'M13 2L3 14h9l-1 8 10-12h-9z',
  check: 'M20 6L9 17l-5-5',
  chevR: 'M9 18l6-6-6-6',
  chevL: 'M15 18l-6-6 6-6',
  chevD: 'M6 9l6 6 6-6',
  dots: 'M12 6h.01 M12 12h.01 M12 18h.01',
  menu: 'M4 6h16 M4 12h16 M4 18h16',
  thumbUp: 'M7 10v12 M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H7V10l4-9a1 1 0 0 1 1 1v3a3 3 0 0 1-.5 1.66Z',
  thumbDown:'M17 14V2 M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H17v12l-4 9a1 1 0 0 1-1-1v-3a3 3 0 0 1 .5-1.66Z',
  copy: 'M20 9h-9a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2v-9a2 2 0 0 0-2-2z M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1',
  user: 'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2 M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8',
  back: 'M19 12H5 M12 19l-7-7 7-7',
  clock: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20 M12 6v6l4 2',
  grid: 'M3 3h8v8H3z M13 3h8v8h-8z M3 13h8v8H3z M13 13h8v8h-8z',
  list: 'M8 6h13 M8 12h13 M8 18h13 M3 6h.01 M3 12h.01 M3 18h.01',
  upload: 'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4 M17 8l-5-5-5 5 M12 3v12',
  globe: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20 M2 12h20 M12 2a15 15 0 0 1 0 20 M12 2a15 15 0 0 0 0 20',
  users: 'M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2 M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8 M23 21v-2a4 4 0 0 0-3-3.87 M16 3.13a4 4 0 0 1 0 7.75',
  folder: 'M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z',
};

function SoliplexMark({ size = 28 }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: size * 0.22, background: '#2F3337',
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
    }}>
      <div style={{ width: size * 0.5, height: size * 0.5, borderRadius: '50%', border: `2px solid #60C7D8`, background: '#2F3337' }} />
    </div>
  );
}

Object.assign(window, {
  SP_LIGHT, SP_DARK, SP_FONT, SP_MONO,
  Icon, ICON, SoliplexMark,
});
