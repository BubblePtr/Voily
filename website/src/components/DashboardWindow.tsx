import { useId, type CSSProperties, type ReactElement } from 'react'

import { AppWindow, TrafficLights } from './AppWindow'
import { OverlayCapsule } from './OverlayCapsule'

// High-fidelity recreation of Voily's Home dashboard (see assets/screenshots/hero.png).
// English-labelled to match the rest of the marketing site.

type NavItem = {
  id: string
  name: string
  icon: () => ReactElement
  active?: boolean
}

type NavGroup = {
  label: string
  items: NavItem[]
}

const navGroups: NavGroup[] = [
  {
    label: 'General',
    items: [{ id: 'home', name: 'Home', icon: HomeIcon, active: true }],
  },
  {
    label: 'Setup',
    items: [
      { id: 'models', name: 'Models', icon: CubeIcon },
      { id: 'dictionary', name: 'Dictionary', icon: BookIcon },
      { id: 'general', name: 'General', icon: SlidersIcon },
      { id: 'input', name: 'Input', icon: KeyIcon },
    ],
  },
  {
    label: 'App',
    items: [{ id: 'about', name: 'About', icon: InfoIcon }],
  },
]

const stats = [
  { tone: 'blue', label: 'Total dictation', value: '4h 35m', caption: 'Across 992 sessions' },
  { tone: 'green', label: 'Total words', value: '54,357', caption: 'Final result text' },
  { tone: 'amber', label: 'Words / minute', value: '197', caption: 'Across all time' },
  { tone: 'pink', label: 'Avg latency', value: '249 ms', caption: 'Record → text', highlight: true },
]

type SceneSegmentSource = {
  name: string
  pct: number
}

type SceneSegment = SceneSegmentSource & {
  color: string
}

type SceneDonutSegment = SceneSegment & {
  visiblePct: number
  hiddenPct: number
  offsetPct: number
}

const sceneSegmentColors = ['#5aa6ff', '#1f86ff', '#0b63d6', '#0a3f93', '#0b2a5e']
const sceneSegmentGapPct = 1.2
export const sceneHourBarDelayStepMs = 45
export const sceneDonutViewBoxSize = 120
export const sceneDonutCenter = sceneDonutViewBoxSize / 2
export const sceneDonutRadius = 47
export const sceneDonutTopY = sceneDonutCenter - sceneDonutRadius

export function buildSceneDonutRevealPath(center: number, radius: number): string {
  const topY = center - radius
  const bottomY = center + radius

  return `M ${center} ${topY} A ${radius} ${radius} 0 1 0 ${center} ${bottomY} A ${radius} ${radius} 0 1 0 ${center} ${topY}`
}

export const sceneDonutCounterclockwiseRevealPath = buildSceneDonutRevealPath(
  sceneDonutCenter,
  sceneDonutRadius,
)
export const sceneDonutRevealMaskLineCap = 'butt'
export const sceneDonutRevealHeadRadius = 8
export const sceneDonutRevealMaskStrokeWidth = sceneDonutRevealHeadRadius * 2
export const sceneDonutSegmentStrokeWidth = 11
export const sceneDonutTerminalCapRadius = sceneDonutSegmentStrokeWidth / 2

// "Where you dictate" donut — share of sessions by front-most app.
const sceneSegmentSources: SceneSegmentSource[] = [
  { name: 'Claude', pct: 37 },
  { name: 'Cursor', pct: 26 },
  { name: 'Codex', pct: 16 },
  { name: 'Google Chrome', pct: 12 },
  { name: 'Discord', pct: 5 },
  { name: 'Notion', pct: 4 },
]

// "When you dictate" — relative activity per ~2h bucket across the day.
const hourBuckets = [40, 12, 8, 9, 11, 20, 85, 54, 78, 100, 58, 72, 46]

export function buildSceneSegments(sources: SceneSegmentSource[]): SceneSegment[] {
  const mainSegments = sources.slice(0, 4).map((segment, index) => ({
    ...segment,
    color: sceneSegmentColors[index],
  }))
  const otherPct = sources.slice(4).reduce((sum, segment) => sum + segment.pct, 0)

  if (otherPct <= 0) {
    return mainSegments
  }

  return [
    ...mainSegments,
    {
      name: 'Others',
      pct: otherPct,
      color: sceneSegmentColors[4],
    },
  ]
}

const sceneSegments = buildSceneSegments(sceneSegmentSources)

export function buildSceneDonutSegments(segments: SceneSegment[]): SceneDonutSegment[] {
  const gap = segments.length > 1 ? sceneSegmentGapPct : 0
  let offsetPct = 0

  return segments.map((segment) => {
    const visiblePct = roundPct(Math.max(0, segment.pct - gap))
    const donutSegment = {
      ...segment,
      visiblePct,
      hiddenPct: roundPct(100 - visiblePct),
      offsetPct: roundPct(offsetPct),
    }

    offsetPct += segment.pct
    return donutSegment
  })
}

export function getSceneDonutTerminalCapColor(segments: SceneSegment[]): string | undefined {
  return segments.at(-1)?.color
}

const sceneDonutSegments = buildSceneDonutSegments(sceneSegments)
const sceneDonutTerminalCapColor = getSceneDonutTerminalCapColor(sceneSegments)

function roundPct(value: number): number {
  return Math.round(value * 10) / 10
}

export function DashboardWindow() {
  return (
    <div className="dashboard-shell">
      <AppWindow className="dashboard-window" flush>
      <div className="dash">
        <aside className="dash-sidebar">
          <div className="dash-sidebar-top">
            <TrafficLights />
            <SidebarToggleIcon />
          </div>
          <div className="dash-brand">
            <img src="/voily-icon.png" alt="" />
            <span>Voily</span>
          </div>
          <nav className="dash-nav">
            {navGroups.map((group) => (
              <div className="dash-nav-group" key={group.label}>
                <span className="dash-nav-label">{group.label}</span>
                {group.items.map((item) => {
                  const Icon = item.icon
                  return (
                    <span
                      className={`dash-nav-item${item.active ? ' is-active' : ''}`}
                      key={item.id}
                    >
                      <Icon />
                      <span>{item.name}</span>
                    </span>
                  )
                })}
              </div>
            ))}
          </nav>
        </aside>

        <div className="dash-main">
          <div className="dash-topbar">
            <div className="dash-title">
              <h3>Home</h3>
              <p>Today's dictation, trends, and full history — all in one place.</p>
            </div>
            <div className="dash-pills">
              <span className="dash-pill">
                <MicIcon />
                Microphone
                <span className="dash-pill-dot" />
              </span>
              <span className="dash-pill">
                <AxIcon />
                Accessibility
                <span className="dash-pill-dot" />
              </span>
            </div>
          </div>

          <div className="dash-stats">
            {stats.map((stat) => (
              <div className={`dash-stat${stat.highlight ? ' is-highlight' : ''}`} key={stat.label}>
                <span className={`dash-stat-dot tone-${stat.tone}`} />
                <span className="dash-stat-label">{stat.label}</span>
                <strong className="dash-stat-value">{stat.value}</strong>
                <span className="dash-stat-caption">{stat.caption}</span>
              </div>
            ))}
          </div>

          <div className="dash-charts">
            <SceneDonut />
            <HoursBars />
          </div>

          <div className="dash-history">
            <div className="dash-history-head">
              <div>
                <h4>History</h4>
                <p>Newest first, with copyable final text.</p>
              </div>
            </div>
            <div className="dash-history-row">
              <div className="dash-history-body">
                <div className="dash-history-meta">
                  <strong>Jun 11, 2026 at 22:31</strong>
                  <span className="dash-history-tag">Injected</span>
                  <span className="dash-history-tag is-muted">Refined</span>
                </div>
                <span className="dash-history-sub">9s · 29 words · Fun-ASR · cloud-realtime · 228 ms</span>
                <p>From a search-intent angle it's the brand keyword — should we optimize a bit?</p>
              </div>
              <span className="dash-history-copy">Copy text</span>
            </div>
          </div>
        </div>
      </div>
      </AppWindow>

      <div className="dash-overlay-dock" aria-hidden="true">
        <OverlayCapsule phase="listening" text="I'm using an AI voice input assistant" />
      </div>
    </div>
  )
}

// Donut of session share by app, with a centred total and a percentage legend.
function SceneDonut() {
  const revealMaskID = useId()

  return (
    <div className="dash-chart dash-scene">
      <div className="dash-chart-head">
        <h5>Where you dictate</h5>
        <p>By front-most app</p>
      </div>
      <div className="scene-body">
        <div className="scene-donut">
          <svg viewBox={`0 0 ${sceneDonutViewBoxSize} ${sceneDonutViewBoxSize}`} aria-hidden="true">
            <defs>
              <mask id={revealMaskID}>
                <rect width={sceneDonutViewBoxSize} height={sceneDonutViewBoxSize} fill="black" />
                <path
                  className="scene-donut-reveal-mask-path"
                  d={sceneDonutCounterclockwiseRevealPath}
                  fill="none"
                  stroke="white"
                  strokeLinecap={sceneDonutRevealMaskLineCap}
                  strokeWidth={sceneDonutRevealMaskStrokeWidth}
                  pathLength="100"
                />
                <g className="scene-donut-reveal-head-orbit">
                  <circle
                    className="scene-donut-reveal-head"
                    cx={sceneDonutCenter}
                    cy={sceneDonutTopY}
                    r={sceneDonutRevealHeadRadius}
                    fill="white"
                  />
                </g>
              </mask>
            </defs>
            <circle
              className="scene-donut-track"
              cx={sceneDonutCenter}
              cy={sceneDonutCenter}
              r={sceneDonutRadius}
              fill="none"
              strokeWidth={sceneDonutSegmentStrokeWidth}
            />
            <g
              className="scene-donut-segments"
              transform={`rotate(-90 ${sceneDonutCenter} ${sceneDonutCenter})`}
              mask={`url(#${revealMaskID})`}
            >
              {sceneDonutSegments.map((s) => (
                <circle
                  key={s.name}
                  className="scene-donut-segment"
                  cx={sceneDonutCenter}
                  cy={sceneDonutCenter}
                  r={sceneDonutRadius}
                  fill="none"
                  stroke={s.color}
                  strokeWidth={sceneDonutSegmentStrokeWidth}
                  strokeLinecap="round"
                  strokeDashoffset={-s.offsetPct}
                  pathLength="100"
                  strokeDasharray={`${s.visiblePct} ${s.hiddenPct}`}
                />
              ))}
            </g>
            {sceneDonutTerminalCapColor && (
              <circle
                className="scene-donut-terminal-cap"
                cx={sceneDonutCenter}
                cy={sceneDonutTopY}
                r={sceneDonutTerminalCapRadius}
                fill={sceneDonutTerminalCapColor}
              />
            )}
          </svg>
          <div className="scene-donut-center">
            <strong>19</strong>
            <span>sessions</span>
          </div>
        </div>
        <ul className="scene-legend">
          {sceneSegments.map((s) => (
            <li key={s.name}>
              <span className="scene-legend-dot" style={{ background: s.color }} />
              <span className="scene-legend-name">{s.name}</span>
              <span className="scene-legend-pct">{s.pct}%</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}

// Time-of-day activity bars; quieter buckets render in a lighter blue.
function HoursBars() {
  const max = Math.max(...hourBuckets)

  return (
    <div className="dash-chart dash-hours">
      <div className="dash-chart-head">
        <h5>When you dictate</h5>
        <p>Your active hours</p>
      </div>
      <div className="hours-bars">
        {hourBuckets.map((v, i) => (
          <span
            key={i}
            className={`hours-bar${v < 18 ? ' is-faint' : ''}`}
            style={
              {
                height: `${Math.max(6, (v / max) * 100)}%`,
                '--bar-delay': `${i * sceneHourBarDelayStepMs}ms`,
              } as CSSProperties
            }
          />
        ))}
      </div>
      <div className="hours-axis">
        <span>0</span>
        <span>12</span>
        <span>24</span>
      </div>
    </div>
  )
}

/* --- inline icons (16px line icons, currentColor) --- */

function svgProps() {
  return {
    width: 15,
    height: 15,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.8,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    'aria-hidden': true,
  }
}

function HomeIcon() {
  return (
    <svg {...svgProps()}>
      <path d="M3 10.5 12 3l9 7.5" />
      <path d="M5 9.5V20h14V9.5" />
    </svg>
  )
}
function CubeIcon() {
  return (
    <svg {...svgProps()}>
      <path d="M12 2.5 21 7v10l-9 4.5L3 17V7z" />
      <path d="M3 7l9 4.5L21 7M12 11.5V21" />
    </svg>
  )
}
function BookIcon() {
  return (
    <svg {...svgProps()}>
      <path d="M5 4h11a2 2 0 0 1 2 2v14H7a2 2 0 0 1-2-2z" />
      <path d="M5 4a2 2 0 0 0-2 2v12" />
    </svg>
  )
}
function SlidersIcon() {
  return (
    <svg {...svgProps()}>
      <path d="M4 7h11M19 7h1M4 17h5M13 17h7" />
      <circle cx="16" cy="7" r="2.2" />
      <circle cx="10" cy="17" r="2.2" />
    </svg>
  )
}
function KeyIcon() {
  return (
    <svg {...svgProps()}>
      <rect x="3" y="6" width="18" height="12" rx="2.5" />
      <path d="M7 10h.01M11 10h.01M15 10h.01M8 14h8" />
    </svg>
  )
}
function InfoIcon() {
  return (
    <svg {...svgProps()}>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 11v5M12 8h.01" />
    </svg>
  )
}
function MicIcon() {
  return (
    <svg {...svgProps()} width={13} height={13}>
      <rect x="9" y="3" width="6" height="11" rx="3" />
      <path d="M5 11a7 7 0 0 0 14 0M12 18v3" />
    </svg>
  )
}
function AxIcon() {
  return (
    <svg {...svgProps()} width={13} height={13}>
      <circle cx="12" cy="4.5" r="1.6" />
      <path d="M4 8h16M12 8v6M12 14l-3 6M12 14l3 6" />
    </svg>
  )
}
function SidebarToggleIcon() {
  return (
    <svg {...svgProps()} width={15} height={15} className="dash-sidebar-toggle">
      <rect x="3" y="5" width="18" height="14" rx="2.5" />
      <path d="M9 5v14" />
    </svg>
  )
}
