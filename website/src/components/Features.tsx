import { useEffect, useRef, useState } from 'react'

import { AppWindow } from './AppWindow'
import { apps } from './content'
import { OverlayCapsule } from './OverlayCapsule'
import { useDictationScene, type SceneExample } from './useDictationScene'

const navItems = ['AI Rewrite', 'In context', 'Always ready']

// Scroll-spy: highlight the nav entry whose section sits closest to the middle
// of the viewport, and tell that section it may animate.
function useActiveSection(count: number) {
  const refs = useRef<(HTMLElement | null)[]>([])
  const setters = useRef<((el: HTMLElement | null) => void)[]>([])
  const [active, setActive] = useState(0)

  useEffect(() => {
    const observer = new IntersectionObserver(
      () => {
        // A crossing fired — pick the section whose center is closest to the
        // viewport center, so overlapping sections never flip to the wrong one.
        const middle = window.innerHeight / 2
        let best = -1
        let bestDist = Infinity
        refs.current.forEach((el, idx) => {
          if (!el) return
          const rect = el.getBoundingClientRect()
          const dist = Math.abs((rect.top + rect.bottom) / 2 - middle)
          if (dist < bestDist) {
            bestDist = dist
            best = idx
          }
        })
        if (best >= 0) setActive(best)
      },
      { rootMargin: '-45% 0px -45% 0px', threshold: 0 }
    )
    refs.current.forEach((el) => el && observer.observe(el))
    return () => observer.disconnect()
  }, [count])

  // Stable per-index ref callback so re-renders don't detach/reattach the node.
  const setRef = (idx: number) => {
    if (!setters.current[idx]) {
      setters.current[idx] = (el: HTMLElement | null) => {
        refs.current[idx] = el
      }
    }
    return setters.current[idx]
  }

  return { active, setRef }
}

export function Features() {
  const { active, setRef } = useActiveSection(3)

  return (
    <section className="features" id="features" aria-labelledby="features-title">
      <h2 id="features-title" className="sr-only">
        How Voily works
      </h2>
      <div className="features-grid">
        <aside className="features-nav" aria-hidden="true">
          <span className="features-nav-kicker">How it works</span>
          <ul>
            {navItems.map((item, i) => (
              <li key={item} className={i === active ? 'is-active' : ''}>
                <span className="features-nav-dot" />
                {item}
              </li>
            ))}
          </ul>
        </aside>

        <div className="features-flow">
          <FeatureBlock
            setRef={setRef(0)}
            idx={0}
            eyebrow="01 — AI Rewrite"
            title={<>Say it rough.<br />Get it polished.</>}
            copy="Not autocorrect — a full rewrite that fixes grammar, trims filler, and matches the tone your context needs. You ramble; Voily ships the clean version."
          >
            <RewriteScene active={active === 0} />
          </FeatureBlock>

          <FeatureBlock
            setRef={setRef(1)}
            idx={1}
            eyebrow="02 — Adapts to context"
            title={<>One voice,<br />every register.</>}
            copy="The same spoken note becomes a concise code comment, a professional email, a casual message, or a structured prompt — shaped for wherever your cursor is."
          >
            <ContextScene active={active === 1} />
          </FeatureBlock>

          <FeatureBlock
            setRef={setRef(2)}
            idx={2}
            eyebrow="03 — Always ready"
            title={<>One shortcut,<br />anywhere you type.</>}
            copy="No app switching, no input panel, no copy-paste. Tap your trigger key and the overlay floats up — right over whatever app you're already in."
          >
            <AnywhereScene active={active === 2} />
          </FeatureBlock>
        </div>
      </div>
    </section>
  )
}

function FeatureBlock(props: {
  setRef: (el: HTMLElement | null) => void
  idx: number
  eyebrow: string
  title: React.ReactNode
  copy: string
  children: React.ReactNode
}) {
  return (
    <article className="feature-block" ref={props.setRef} data-idx={props.idx}>
      <div className="feature-copy">
        <span className="feature-eyebrow">{props.eyebrow}</span>
        <h3>{props.title}</h3>
        <p>{props.copy}</p>
      </div>
      <div className="feature-stage">{props.children}</div>
    </article>
  )
}

/* ---------------- Scene 1: AI Rewrite (Slack-style compose) ---------------- */

const rewriteExamples: SceneExample[] = [
  {
    app: 'Slack',
    said: 'tell jason the api bug is fixed, he can pull latest main',
    writes: 'Hey Jason — the API bug is fixed. Pull the latest from main when you get a chance. 🙌',
  },
]

function RewriteScene({ active }: { active: boolean }) {
  const view = useDictationScene(rewriteExamples, active)
  const ex = rewriteExamples[view.index]
  const typing = view.phase === 'injecting' && view.output !== ex.writes
  const sent = view.phase === 'injecting' && view.output === ex.writes
  const composeText = typing ? view.output : ''

  return (
    <div className="scene scene-rewrite">
      <AppWindow
        className="chat-window"
        toolbar={
          <div className="win-toolbar-inner">
            <span className="chat-workspace">
              <span className="chat-workspace-badge">A</span>
              Acme
            </span>
            <span className="chat-channel"># engineering</span>
          </div>
        }
      >
        <div className="chat-thread">
          <div className="chat-msg">
            <span className="chat-avatar tone-amber">J</span>
            <div>
              <span className="chat-name">
                Jason Wu <em>9:41</em>
              </span>
              <p>any luck on that auth bug from this morning?</p>
            </div>
          </div>
          {sent ? (
            <div className="chat-msg chat-msg-me is-sent">
              <span className="chat-avatar tone-blue">K</span>
              <div>
                <span className="chat-name">
                  You <em>now</em>
                </span>
                <p>{ex.writes}</p>
              </div>
            </div>
          ) : null}
        </div>
        <div className="chat-compose">
          <span className={`chat-input${composeText ? '' : ' is-empty'}`}>
            {composeText || 'Message #engineering'}
            {typing ? <span className="chat-caret" /> : null}
          </span>
          <span className={`chat-send${typing || sent ? ' is-ready' : ''}`} aria-hidden="true">
            ➤
          </span>
        </div>
      </AppWindow>

      <div className="scene-dock">
        <OverlayCapsule phase={view.phase} text={view.capsuleText} />
      </div>
    </div>
  )
}

/* ---------------- Scene 2: Refine for the moment (context tabs) ---------------- */

type ContextExample = SceneExample & { tab: string; kind: 'code' | 'mail' | 'chat' | 'prompt' }

const contextExamples: ContextExample[] = [
  {
    tab: 'Code comment',
    kind: 'code',
    app: 'Cursor',
    said: 'this function cleans up the user input and saves it to the database',
    writes: '// Sanitizes raw user input and persists\n// the cleaned result to the database.',
  },
  {
    tab: 'Email',
    kind: 'mail',
    app: 'Gmail',
    said: 'tell the client the project is delayed one week, waiting on a third party api',
    writes:
      "Hi — a quick timeline update: we're waiting on a third-party API integration, which pushes delivery back by about one week. I'll keep you posted.",
  },
  {
    tab: 'Message',
    kind: 'chat',
    app: 'Slack',
    said: 'lunch got moved to one, meet downstairs',
    writes: "Heads up — lunch moved to 1pm. Let's meet downstairs 👍",
  },
  {
    tab: 'Prompt',
    kind: 'prompt',
    app: 'ChatGPT',
    said: 'write a prompt that makes gpt find outliers in this csv',
    writes:
      'Analyze the attached CSV. Identify statistical outliers in each numeric column using the IQR method, flag the rows, and explain why each value is anomalous.',
  },
]

function ContextScene({ active }: { active: boolean }) {
  const view = useDictationScene(contextExamples, active)
  const ex = contextExamples[view.index]
  const shown = view.output || (view.phase === 'injecting' ? ex.writes : '')

  return (
    <div className="scene scene-context">
      <AppWindow
        className="context-window"
        toolbar={
          <div className="win-toolbar-inner">
            <span className="context-app">{ex.app}</span>
            <span className="context-said">“{ex.said}”</span>
          </div>
        }
      >
        <div className="context-tabs">
          {contextExamples.map((c, i) => (
            <span key={c.tab} className={`context-tab${i === view.index ? ' is-active' : ''}`}>
              {c.tab}
            </span>
          ))}
        </div>
        <div className={`context-output kind-${ex.kind}`}>
          {shown ? (
            <p>{shown}</p>
          ) : (
            <span className="context-waiting">{view.phase === 'refining' ? 'Refining…' : 'Listening…'}</span>
          )}
        </div>
      </AppWindow>

      <div className="scene-dock">
        <OverlayCapsule phase={view.phase} text={view.capsuleText} />
      </div>
    </div>
  )
}

/* ---------------- Scene 3: Always Ready (floating overlay) ---------------- */

const anywhereExamples: SceneExample[] = [
  {
    app: 'Anywhere',
    said: 'add a note — ship the release on friday',
    writes: 'Note: ship the release on Friday.',
  },
]

// Derive the desktop dock icons from the shared app list so icon paths live in
// one place (content.ts).
const desktopAppNames = new Set(['Cursor', 'Slack', 'Gmail', 'Notion', 'ChatGPT'])
const desktopApps = apps.filter((app) => desktopAppNames.has(app.name)).map((app) => app.iconPath)

function AnywhereScene({ active }: { active: boolean }) {
  const view = useDictationScene(anywhereExamples, active)

  return (
    <div className="scene scene-anywhere">
      <div className="desktop">
        <div className="desktop-glow" />
        <div className="desktop-dock">
          {desktopApps.map((src) => (
            <img key={src} src={src} alt="" aria-hidden="true" />
          ))}
        </div>
        <span className="desktop-key" data-pressed={view.phase === 'listening'}>
          <kbd>fn</kbd>
          <span>trigger</span>
        </span>
        <div className="anywhere-dock">
          <OverlayCapsule phase={view.phase} text={view.capsuleText} />
        </div>
      </div>
    </div>
  )
}
