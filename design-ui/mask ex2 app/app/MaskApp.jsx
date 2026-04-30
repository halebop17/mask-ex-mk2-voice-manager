// Mask1EX MK2 Voice Organizer — native macOS app design
// Visual vocabulary: dense Mac utility (Audio MIDI Setup, Logic preset browser).
// SF system font, SF Mono for slot/voice, faint pane tints, 22px rows.

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif';
const MONO = '"SF Mono", ui-monospace, Menlo, monospace';

// ─── tokens ──────────────────────────────────────────────────────────────
const T = {
  // window chrome
  titlebar:    '#E8E8E8',
  titlebarBdr: '#D5D5D5',
  toolbar:     '#ECECEC',
  // panes
  paneBg:      '#FFFFFF',
  paneHdr:     '#F6F6F6',
  divider:     '#E0E0E0',
  rowAlt:      '#FAFAFA',
  // text
  text:        '#1D1D1F',
  text2:       '#6E6E73',
  text3:       '#A1A1A6',
  // accents
  blue:        '#0A84FF',
  blueSel:     '#0A84FF',
  selBg:       '#D0E4FF',  // inactive selection
  // pane tints (very faint washes)
  yellowTint:  'rgba(255, 214, 64, 0.10)',
  yellowEdge:  'rgba(212, 168, 36, 0.35)',
  yellowDot:   '#E8B923',
  greenTint:   'rgba(48, 209, 88, 0.10)',
  greenEdge:   'rgba(40, 162, 79, 0.30)',
  greenDot:    '#34A853',
  // status
  connected:   '#30D158',
  modified:    '#FF9F0A',
};

// ─── window chrome (custom — denser than the starter) ───────────────────
function MacWin({ width = 1200, height = 720, title, children }) {
  return (
    <div style={{
      width, height, borderRadius: 10, overflow: 'hidden',
      background: T.paneBg, fontFamily: FONT, color: T.text,
      boxShadow: '0 0 0 0.5px rgba(0,0,0,0.35), 0 24px 60px rgba(0,0,0,0.30), 0 6px 18px rgba(0,0,0,0.18)',
      display: 'flex', flexDirection: 'column',
    }}>
      <Titlebar title={title} />
      {children}
    </div>
  );
}

function Titlebar({ title }) {
  const dot = (bg) => (
    <div style={{
      width: 12, height: 12, borderRadius: '50%', background: bg,
      boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.18)',
    }} />
  );
  return (
    <div style={{
      height: 28, background: T.titlebar,
      borderBottom: `0.5px solid ${T.titlebarBdr}`,
      display: 'grid', gridTemplateColumns: '1fr auto 1fr', alignItems: 'center',
      padding: '0 12px', flexShrink: 0,
    }}>
      <div style={{ display: 'flex', gap: 8 }}>
        {dot('#FF5F57')}{dot('#FEBC2E')}{dot('#28C840')}
      </div>
      <div style={{ fontSize: 13, fontWeight: 500, color: T.text, letterSpacing: -0.1 }}>
        {title}
      </div>
      <div />
    </div>
  );
}

// ─── SF-style icons (stroke 1.5, currentColor) ──────────────────────────
const Icon = {
  download: (s=14) => (
    <svg width={s} height={s} viewBox="0 0 16 16" fill="none">
      <path d="M8 2v9M4.5 7.5L8 11l3.5-3.5M3 13h10" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  upload: (s=14) => (
    <svg width={s} height={s} viewBox="0 0 16 16" fill="none">
      <path d="M8 12V3M4.5 6.5L8 3l3.5 3.5M3 13h10" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  doc: (s=14) => (
    <svg width={s} height={s} viewBox="0 0 16 16" fill="none">
      <path d="M3.5 2h6L12.5 5v9h-9V2z M9.5 2v3h3" stroke="currentColor" strokeWidth="1.3" strokeLinejoin="round"/>
    </svg>
  ),
  csv: (s=14) => (
    <svg width={s} height={s} viewBox="0 0 16 16" fill="none">
      <path d="M3 3h7l3 3v7H3z" stroke="currentColor" strokeWidth="1.3" strokeLinejoin="round"/>
      <path d="M5.5 9.5h1.5M5.5 11.5h2M9 9.5h2M9 11.5h2.5" stroke="currentColor" strokeWidth="1" strokeLinecap="round"/>
    </svg>
  ),
  send: (s=14) => (
    <svg width={s} height={s} viewBox="0 0 16 16" fill="none">
      <path d="M2 8h11M9 4l4 4-4 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  arrowR: (s=12) => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <path d="M2 6h8M7 3l3 3-3 3" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  arrowL: (s=12) => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <path d="M10 6H2M5 3L2 6l3 3" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  search: (s=12) => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <circle cx="5" cy="5" r="3.3" stroke="currentColor" strokeWidth="1.3"/>
      <path d="M7.5 7.5l2.3 2.3" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round"/>
    </svg>
  ),
  plug: (s=12) => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <path d="M4 1v3M8 1v3M3 4h6v2.5a3 3 0 01-3 3 3 3 0 01-3-3V4zM6 9.5V11" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  reorder: (s=10) => (
    <svg width={s} height={s} viewBox="0 0 10 10" fill="none">
      <circle cx="3.5" cy="2.5" r="0.7" fill="currentColor"/><circle cx="6.5" cy="2.5" r="0.7" fill="currentColor"/>
      <circle cx="3.5" cy="5" r="0.7" fill="currentColor"/><circle cx="6.5" cy="5" r="0.7" fill="currentColor"/>
      <circle cx="3.5" cy="7.5" r="0.7" fill="currentColor"/><circle cx="6.5" cy="7.5" r="0.7" fill="currentColor"/>
    </svg>
  ),
};

// ─── tiny UI primitives ─────────────────────────────────────────────────
function TbButton({ icon, label, primary, disabled, compact }) {
  const pad = compact ? '0 8px' : '0 10px';
  if (primary) {
    return (
      <button style={{
        height: 22, padding: pad, border: 'none', borderRadius: 5,
        background: 'linear-gradient(180deg, #4DA3FF 0%, #0A84FF 100%)',
        color: '#fff', fontFamily: FONT, fontSize: 12, fontWeight: 500,
        display: 'flex', alignItems: 'center', gap: 5,
        boxShadow: '0 0.5px 0 rgba(0,0,0,0.15), inset 0 0.5px 0 rgba(255,255,255,0.4)',
        cursor: 'pointer',
      }}>
        {icon}{label}
      </button>
    );
  }
  return (
    <button disabled={disabled} style={{
      height: 22, padding: pad,
      border: '0.5px solid rgba(0,0,0,0.18)', borderRadius: 5,
      background: disabled ? '#F5F5F5' : 'linear-gradient(180deg, #FFFFFF 0%, #F4F4F4 100%)',
      color: disabled ? T.text3 : T.text,
      fontFamily: FONT, fontSize: 12, fontWeight: 400,
      display: 'flex', alignItems: 'center', gap: 5,
      boxShadow: '0 0.5px 0 rgba(0,0,0,0.04)', cursor: disabled ? 'default' : 'pointer',
    }}>
      {icon}{label}
    </button>
  );
}

function StatusPill({ connected }) {
  return (
    <div style={{
      height: 22, padding: '0 10px 0 8px',
      border: `0.5px solid ${connected ? 'rgba(48,209,88,0.45)' : 'rgba(0,0,0,0.18)'}`,
      borderRadius: 11,
      background: connected ? 'rgba(48,209,88,0.10)' : '#F5F5F5',
      display: 'flex', alignItems: 'center', gap: 6,
      fontSize: 11.5, fontWeight: 500, color: connected ? '#0E6F2E' : T.text2,
    }}>
      <span style={{
        width: 7, height: 7, borderRadius: '50%',
        background: connected ? T.connected : '#C7C7CC',
        boxShadow: connected ? '0 0 0 2px rgba(48,209,88,0.18)' : 'none',
      }} />
      {connected ? 'Connected · Mask1EX MK2' : 'Disconnected'}
    </div>
  );
}

function SearchField({ placeholder = 'Search', value = '', accent }) {
  return (
    <div style={{
      flex: 1, height: 20, borderRadius: 4,
      background: '#fff', border: '0.5px solid rgba(0,0,0,0.18)',
      display: 'flex', alignItems: 'center', gap: 5, padding: '0 6px',
      boxShadow: 'inset 0 0.5px 1px rgba(0,0,0,0.04)',
    }}>
      <span style={{ color: T.text3, display: 'flex' }}>{Icon.search(11)}</span>
      <span style={{
        flex: 1, fontSize: 11.5, color: value ? T.text : T.text3,
        fontFamily: FONT,
      }}>{value || placeholder}</span>
    </div>
  );
}

// ─── voice list ─────────────────────────────────────────────────────────
function PaneHeader({ side, title, count, accent, accentDot }) {
  return (
    <div style={{
      height: 38, padding: '0 10px',
      background: `linear-gradient(180deg, ${accent} 0%, ${accent} 100%), ${T.paneHdr}`,
      backgroundBlendMode: 'normal',
      borderBottom: `0.5px solid ${T.divider}`,
      display: 'flex', alignItems: 'center', gap: 8,
    }}>
      <span style={{
        width: 7, height: 7, borderRadius: 2, background: accentDot,
        boxShadow: '0 0 0 0.5px rgba(0,0,0,0.1)',
      }} />
      <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <div style={{ fontSize: 12, fontWeight: 600, color: T.text, lineHeight: 1.1 }}>
          {title}
        </div>
        <div style={{ fontSize: 10.5, color: T.text2, fontFamily: MONO, marginTop: 1 }}>
          {count}
        </div>
      </div>
    </div>
  );
}

function ColHeaders({ showModDot }) {
  return (
    <div style={{
      height: 20, display: 'flex', alignItems: 'center',
      borderBottom: `0.5px solid ${T.divider}`,
      background: '#FBFBFB',
      fontSize: 10, fontWeight: 600, color: T.text2,
      textTransform: 'uppercase', letterSpacing: 0.3,
      padding: '0 10px',
    }}>
      <div style={{ width: 36 }}>#</div>
      <div style={{ flex: 1 }}>Name</div>
      <div style={{ width: 32, textAlign: 'right' }}>Tag</div>
      {showModDot && <div style={{ width: 14 }} />}
    </div>
  );
}

function VoiceRow({
  slot, name, tag, modified, selected, focused, alt,
  renaming, renameValue, accentTag, showMod,
}) {
  const bg = renaming ? '#fff'
    : selected && focused ? T.blueSel
    : selected ? T.selBg
    : alt ? T.rowAlt : 'transparent';
  const fg = (selected && focused) ? '#fff' : T.text;
  const fg2 = (selected && focused) ? 'rgba(255,255,255,0.85)' : T.text2;

  return (
    <div style={{
      height: 22, display: 'flex', alignItems: 'center',
      padding: '0 10px', background: bg, color: fg,
      borderBottom: `0.5px solid ${alt || selected ? 'transparent' : 'rgba(0,0,0,0.025)'}`,
    }}>
      <div style={{ width: 36, fontFamily: MONO, fontSize: 11, color: fg2, fontVariantNumeric: 'tabular-nums' }}>
        {slot}
      </div>
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 6, minWidth: 0 }}>
        {renaming ? (
          <div style={{
            display: 'flex', alignItems: 'center',
            border: `1.5px solid ${T.blue}`, borderRadius: 3,
            padding: '0 4px', height: 18, background: '#fff',
            boxShadow: '0 0 0 3px rgba(10,132,255,0.18)',
          }}>
            <span style={{ fontFamily: MONO, fontSize: 11.5, color: T.text, whiteSpace: 'pre' }}>
              {renameValue}
            </span>
            <span style={{
              width: 1, height: 12, background: T.blue, marginLeft: 1,
              animation: 'mk-caret 1s steps(2) infinite',
            }} />
          </div>
        ) : (
          <span style={{ fontFamily: MONO, fontSize: 11.5, whiteSpace: 'pre' }}>{name}</span>
        )}
      </div>
      <div style={{
        width: 32, textAlign: 'right', display: 'flex', justifyContent: 'flex-end',
      }}>
        {tag && tag.trim() && (
          <span style={{
            fontFamily: MONO, fontSize: 9.5, fontWeight: 600,
            padding: '1px 5px', borderRadius: 3,
            background: (selected && focused) ? 'rgba(255,255,255,0.22)' : accentTag,
            color: (selected && focused) ? '#fff' : T.text2,
            letterSpacing: 0.3,
          }}>
            {tag.trim()}
          </span>
        )}
      </div>
      {showMod && (
        <div style={{ width: 14, display: 'flex', justifyContent: 'center' }}>
          {modified && (
            <span style={{
              width: 6, height: 6, borderRadius: '50%',
              background: (selected && focused) ? '#fff' : T.modified,
            }} />
          )}
        </div>
      )}
    </div>
  );
}

// ─── pane ───────────────────────────────────────────────────────────────
function Pane({
  side, title, voices, selectedSet, focusedPane, paneId,
  countLabel, accent, accentEdge, accentDot, accentTag,
  toolbarLeft, toolbarRight, searchValue,
  showMod = false, renamingIdx = -1, renameValue = '',
  scrollOffset = 0, visibleCount = 18,
}) {
  const focused = focusedPane === paneId;
  const slice = voices.slice(scrollOffset, scrollOffset + visibleCount);

  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      background: T.paneBg, minWidth: 0,
      borderTop: `2px solid ${accentEdge}`,
    }}>
      <PaneHeader
        side={side} title={title} count={countLabel}
        accent={accent} accentDot={accentDot}
      />

      {/* per-pane action toolbar */}
      <div style={{
        height: 30, display: 'flex', alignItems: 'center', gap: 5,
        padding: '0 8px',
        borderBottom: `0.5px solid ${T.divider}`,
        background: '#FAFAFA',
      }}>
        {toolbarLeft}
        <div style={{ flex: 1 }} />
        {toolbarRight}
      </div>

      {/* search */}
      <div style={{
        height: 26, display: 'flex', alignItems: 'center',
        padding: '0 8px', borderBottom: `0.5px solid ${T.divider}`,
        background: '#fff',
      }}>
        <SearchField placeholder={`Search ${title.toLowerCase()}`} value={searchValue} />
      </div>

      <ColHeaders showModDot={showMod} />

      {/* rows */}
      <div style={{ flex: 1, overflow: 'hidden', position: 'relative', background: T.paneBg }}>
        {slice.map(([slot, name, tag, modified], i) => {
          const realIdx = scrollOffset + i;
          return (
            <VoiceRow
              key={realIdx}
              slot={slot} name={name} tag={tag} modified={modified}
              selected={selectedSet.has(realIdx)}
              focused={focused}
              alt={i % 2 === 1}
              renaming={renamingIdx === realIdx}
              renameValue={renameValue}
              accentTag={accentTag}
              showMod={showMod}
            />
          );
        })}
        {/* scrollbar */}
        <div style={{
          position: 'absolute', right: 2, top: 4, bottom: 4, width: 5,
        }}>
          <div style={{
            position: 'absolute', right: 0, width: 5,
            top: `${(scrollOffset / voices.length) * 100}%`,
            height: `${(visibleCount / voices.length) * 100}%`,
            background: 'rgba(0,0,0,0.22)', borderRadius: 3,
          }} />
        </div>
      </div>
    </div>
  );
}

// ─── divider with copy buttons ──────────────────────────────────────────
function CopyDivider({ direction = 'both' }) {
  const Btn = ({ children, hint }) => (
    <button style={{
      width: 28, height: 24, border: '0.5px solid rgba(0,0,0,0.18)',
      borderRadius: 5, background: 'linear-gradient(180deg, #FFF 0%, #F4F4F4 100%)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      color: T.text, cursor: 'pointer',
      boxShadow: '0 0.5px 0 rgba(0,0,0,0.04)',
    }} title={hint}>
      {children}
    </button>
  );
  return (
    <div style={{
      width: 36, background: '#F2F2F2',
      borderLeft: `0.5px solid ${T.divider}`,
      borderRight: `0.5px solid ${T.divider}`,
      display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center', gap: 6,
    }}>
      <Btn hint="Copy selection to User Bank">{Icon.arrowR(13)}</Btn>
      <Btn hint="Copy selection to Temporary">{Icon.arrowL(13)}</Btn>
    </div>
  );
}

// ─── status bar ─────────────────────────────────────────────────────────
function StatusBar({ progress, toast }) {
  return (
    <div style={{
      height: 26, flexShrink: 0,
      borderTop: `0.5px solid ${T.divider}`,
      background: T.toolbar,
      display: 'flex', alignItems: 'center', padding: '0 10px',
      fontSize: 11, color: T.text2, gap: 12,
    }}>
      {progress ? (
        <>
          <div style={{
            width: 12, height: 12, borderRadius: '50%',
            border: `1.5px solid ${T.blue}`, borderRightColor: 'transparent',
            animation: 'mk-spin 0.9s linear infinite',
          }} />
          <span style={{ color: T.text }}>{progress.label}</span>
          <div style={{
            width: 220, height: 6, background: '#DCDCDC', borderRadius: 3, overflow: 'hidden',
          }}>
            <div style={{
              width: `${progress.pct}%`, height: '100%',
              background: 'linear-gradient(90deg, #5AB1FF 0%, #0A84FF 100%)',
              borderRadius: 3,
              transition: 'width 0.3s',
            }} />
          </div>
          <span style={{ fontFamily: MONO, fontSize: 10.5, color: T.text2, fontVariantNumeric: 'tabular-nums' }}>
            {progress.pct}%
          </span>
          <div style={{ flex: 1 }} />
          <button style={{
            height: 18, padding: '0 8px', fontSize: 11,
            border: '0.5px solid rgba(0,0,0,0.18)', borderRadius: 4,
            background: '#fff', color: T.text, cursor: 'pointer',
          }}>Cancel</button>
        </>
      ) : (
        <>
          <span style={{ color: T.text2 }}>Ready</span>
          <div style={{ flex: 1 }} />
          {toast && (
            <span style={{
              padding: '2px 8px', borderRadius: 3,
              background: 'rgba(48,209,88,0.12)',
              color: '#0E6F2E', fontSize: 11, fontWeight: 500,
            }}>
              {toast}
            </span>
          )}
        </>
      )}
    </div>
  );
}

// ─── main top toolbar ───────────────────────────────────────────────────
function TopToolbar({ connected }) {
  return (
    <div style={{
      height: 44, flexShrink: 0,
      background: T.toolbar,
      borderBottom: `0.5px solid ${T.divider}`,
      display: 'flex', alignItems: 'center', padding: '0 12px', gap: 10,
    }}>
      <StatusPill connected={connected} />
      <TbButton
        icon={<span style={{ display: 'flex' }}>{Icon.plug(12)}</span>}
        label={connected ? 'Disconnect' : 'Connect'}
      />
      <div style={{ width: 1, height: 22, background: T.divider, margin: '0 4px' }} />
      <div style={{ flex: 1 }} />
      <span style={{ fontSize: 11, color: T.text3, fontFamily: MONO }}>
        v2.0 · macOS 13+
      </span>
    </div>
  );
}

// ─── pane action groups ─────────────────────────────────────────────────
function FactoryToolbarLeft() {
  return (
    <>
      <TbButton icon={Icon.download()} label="From device" />
      <TbButton icon={Icon.doc()} label="From file…" />
    </>
  );
}
function FactoryToolbarRight() {
  return <TbButton icon={Icon.csv()} label="CSV" compact />;
}
function UserToolbarLeft() {
  return (
    <>
      <TbButton icon={Icon.download()} label="From device" />
      <TbButton icon={Icon.doc()} label="From file…" />
      <TbButton icon={Icon.upload()} label="Save bank…" />
    </>
  );
}
function UserToolbarRight() {
  return (
    <>
      <TbButton icon={Icon.csv()} label="CSV" compact />
      <div style={{ width: 1, height: 18, background: T.divider, margin: '0 2px' }} />
      <TbButton icon={Icon.send()} label="Send to MASK1" primary />
    </>
  );
}

// ─── frame composer ─────────────────────────────────────────────────────
function MaskFrame({
  width = 1180, height = 720,
  connected = true,
  factoryScroll = 0, userScroll = 0,
  factorySel = new Set(), userSel = new Set(),
  focusedPane = 'user',
  renamingIdx = -1, renameValue = '',
  progress = null, toast = null,
}) {
  return (
    <MacWin width={width} height={height} title="Mask1EX MK2 Voice Organizer">
      <TopToolbar connected={connected} />

      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        <Pane
          side="left" paneId="factory"
          title="Temporary"
          countLabel={`${window.FACTORY_VOICES.length} voices · max 377`}
          accent={T.yellowTint} accentEdge={T.yellowEdge} accentDot={T.yellowDot}
          accentTag="rgba(232,185,35,0.14)"
          voices={window.FACTORY_VOICES}
          selectedSet={factorySel} focusedPane={focusedPane}
          toolbarLeft={<FactoryToolbarLeft />} toolbarRight={<FactoryToolbarRight />}
          searchValue=""
          scrollOffset={factoryScroll}
        />
        <CopyDivider />
        <Pane
          side="right" paneId="user"
          title="User Bank"
          countLabel={`${window.USER_VOICES.length} of 200 voices`}
          accent={T.greenTint} accentEdge={T.greenEdge} accentDot={T.greenDot}
          accentTag="rgba(52,168,83,0.14)"
          voices={window.USER_VOICES}
          selectedSet={userSel} focusedPane={focusedPane}
          toolbarLeft={<UserToolbarLeft />} toolbarRight={<UserToolbarRight />}
          searchValue=""
          showMod
          renamingIdx={renamingIdx} renameValue={renameValue}
          scrollOffset={userScroll}
        />
      </div>

      <StatusBar progress={progress} toast={toast} />
    </MacWin>
  );
}

// ─── animations & global polish ─────────────────────────────────────────
if (typeof document !== 'undefined' && !document.getElementById('mk-styles')) {
  const s = document.createElement('style');
  s.id = 'mk-styles';
  s.textContent = `
    @keyframes mk-spin { to { transform: rotate(360deg); } }
    @keyframes mk-caret { 50% { opacity: 0; } }
    button { font-family: ${FONT}; }
    button:focus { outline: none; }
  `;
  document.head.appendChild(s);
}

window.MaskFrame = MaskFrame;
