import { useEffect, useRef } from 'react'

// Faithful recreation of the app's floating overlay capsule.
// Waveform envelope mirrors WaveformView in OverlayPanelController.swift so the
// motion reads as the real product, not a generic equalizer.

export type CapsulePhase =
  | 'idle'
  | 'listening'
  | 'transcribing'
  | 'refining'
  | 'injecting'

const BAR_WEIGHTS = [0.58, 0.88, 1.0, 0.84, 0.62]
const BAR_POSITIONS = [-2, -1, 0, 1, 2]
const SPATIAL_PHASE_STEP = Math.PI / 3.2
const LOOP_DURATION = 0.84 // seconds, matches the app
const BAR_MIN = 9
const BAR_MAX = 30

// Target "loudness" per phase. Listening is lively; processing phases settle.
function rmsFloor(phase: CapsulePhase): number {
  switch (phase) {
    case 'listening':
      return 0.92
    case 'transcribing':
      return 0.34
    case 'refining':
      return 0.26
    case 'injecting':
      return 0.16
    default:
      return 0.18
  }
}

// Synthesised speech-like loudness so the bars feel driven by a real voice.
function liveRms(phase: CapsulePhase, t: number): number {
  if (phase === 'listening') {
    const a = (Math.sin(t * 6.1) + 1) * 0.5
    const b = (Math.sin(t * 11.7 + 1.3) + 1) * 0.5
    const c = (Math.sin(t * 2.3 + 0.6) + 1) * 0.5
    const env = 0.45 + 0.55 * (a * 0.5 + b * 0.3 + c * 0.2)
    return Math.min(1, Math.max(0.4, env))
  }
  return rmsFloor(phase)
}

function barHeight(index: number, time: number, rms: number): number {
  const cycle = (time % LOOP_DURATION) / LOOP_DURATION
  const phase = cycle * Math.PI * 2
  const localPhase = phase - BAR_POSITIONS[index] * SPATIAL_PHASE_STEP
  const primary = (Math.sin(localPhase) + 1) * 0.5
  const secondary = (Math.sin(localPhase * 2 - Math.PI / 6) + 1) * 0.5
  const envelope = primary * 0.82 + secondary * 0.18
  const activity = Math.max(0.18, Math.min(1, rms))
  const range = (BAR_MAX - BAR_MIN) * BAR_WEIGHTS[index] * activity
  return BAR_MIN + range * envelope
}

function Waveform({ phase }: { phase: CapsulePhase }) {
  const barsRef = useRef<(HTMLSpanElement | null)[]>([])
  const barSetters = useRef<((el: HTMLSpanElement | null) => void)[]>([])
  const phaseRef = useRef(phase)
  phaseRef.current = phase

  // Stable per-bar ref callback so re-renders don't detach/reattach each node.
  const setBarRef = (i: number) => {
    if (!barSetters.current[i]) {
      barSetters.current[i] = (el: HTMLSpanElement | null) => {
        barsRef.current[i] = el
      }
    }
    return barSetters.current[i]
  }

  // Empty deps on purpose: the rAF loop runs for the component's lifetime and
  // reads the latest phase via phaseRef, so it never needs to restart.
  useEffect(() => {
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    if (reduce) {
      barsRef.current.forEach((bar, i) => {
        if (bar) bar.style.transform = `scaleY(${barHeight(i, 0.42, 0.6) / BAR_MAX})`
      })
      return
    }

    let raf = 0
    const start = performance.now()
    const tick = (now: number) => {
      const t = (now - start) / 1000
      const rms = liveRms(phaseRef.current, t)
      for (let i = 0; i < BAR_WEIGHTS.length; i += 1) {
        const bar = barsRef.current[i]
        if (bar) bar.style.transform = `scaleY(${barHeight(i, t, rms) / BAR_MAX})`
      }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [])

  return (
    <span className="oc-wave" aria-hidden="true">
      {BAR_WEIGHTS.map((_, i) => (
        <span className="oc-bar" key={i} ref={setBarRef(i)} />
      ))}
    </span>
  )
}

type OverlayCapsuleProps = {
  phase: CapsulePhase
  text: string
  className?: string
}

const STATUS_LABEL: Partial<Record<CapsulePhase, string>> = {
  transcribing: 'Transcribing…',
  refining: 'Refining…',
  injecting: 'Injecting…',
}

export function OverlayCapsule({ phase, text, className }: OverlayCapsuleProps) {
  const display = text || STATUS_LABEL[phase] || (phase === 'listening' ? 'Listening…' : '')
  const isPlaceholder = !text

  return (
    <div className={`overlay-capsule${className ? ` ${className}` : ''}`} data-phase={phase}>
      <Waveform phase={phase} />
      <div className="oc-text-viewport">
        <span className={`oc-text${isPlaceholder ? ' is-placeholder' : ''}`}>{display}</span>
      </div>
    </div>
  )
}
