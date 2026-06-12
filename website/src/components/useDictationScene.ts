import { useEffect, useRef, useState } from 'react'

import type { CapsulePhase } from './OverlayCapsule'

export type SceneExample = {
  app: string
  said: string
  writes: string
}

export type SceneView = {
  phase: CapsulePhase
  capsuleText: string
  output: string
  injected: boolean
  index: number
}

// Dictation phase timeline, in ms from the start of each loop. The phases run:
// listen+type → hold → transcribe → refine → inject(type) → hold, then repeat.
const TYPE_SAID_MS = 1700 // time to type out the spoken text
const LISTEN_TYPING_END = 1900 // listening while the typed text settles
const LISTEN_HOLD_END = 2900 // full spoken text held before processing
const TRANSCRIBE_END = 3400
const REFINE_END = 4200
const INJECT_TYPE_MS = 950 // time to type the injected result
const INJECT_TYPING_END = 5300 // result fully injected, then held until LOOP_MS
const LOOP_MS = 7200

// Frozen frame shown when the scene is off-screen or motion is reduced.
const REDUCED_MOTION_ELAPSED_MS = 5000

// One full dictation cycle expressed as a pure function of elapsed time, so the
// loop can be paused/resumed and stays in sync with the waveform.
function viewAt(totalElapsed: number, examples: SceneExample[]): SceneView {
  if (examples.length === 0) return RESTING
  const index = Math.floor(totalElapsed / LOOP_MS) % examples.length
  const t = totalElapsed % LOOP_MS
  const { said, writes } = examples[index]

  if (t < LISTEN_TYPING_END) {
    const p = Math.min(1, t / TYPE_SAID_MS)
    return {
      phase: 'listening',
      capsuleText: said.slice(0, Math.ceil(said.length * p)),
      output: '',
      injected: false,
      index,
    }
  }
  if (t < LISTEN_HOLD_END) {
    return { phase: 'listening', capsuleText: said, output: '', injected: false, index }
  }
  if (t < TRANSCRIBE_END) {
    return { phase: 'transcribing', capsuleText: '', output: '', injected: false, index }
  }
  if (t < REFINE_END) {
    return { phase: 'refining', capsuleText: '', output: '', injected: false, index }
  }
  if (t < INJECT_TYPING_END) {
    const p = Math.min(1, (t - REFINE_END) / INJECT_TYPE_MS)
    return {
      phase: 'injecting',
      capsuleText: '',
      output: writes.slice(0, Math.ceil(writes.length * p)),
      injected: true,
      index,
    }
  }
  // hold the finished result, then fade handled by the consumer
  return { phase: 'injecting', capsuleText: '', output: writes, injected: true, index }
}

const RESTING: SceneView = {
  phase: 'listening',
  capsuleText: '',
  output: '',
  injected: false,
  index: 0,
}

export function useDictationScene(examples: SceneExample[], active: boolean): SceneView {
  const [view, setView] = useState<SceneView>(RESTING)
  const startRef = useRef<number | null>(null)
  const lastRef = useRef<string>('')

  useEffect(() => {
    if (!active) {
      startRef.current = null
      return
    }
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    if (reduce) {
      setView(viewAt(REDUCED_MOTION_ELAPSED_MS, examples))
      return
    }

    let raf = 0
    const tick = (now: number) => {
      if (startRef.current === null) startRef.current = now
      const next = viewAt(now - startRef.current, examples)
      const sig = `${next.index}|${next.phase}|${next.capsuleText.length}|${next.output.length}`
      if (sig !== lastRef.current) {
        lastRef.current = sig
        setView(next)
      }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [active, examples])

  return view
}
