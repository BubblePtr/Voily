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

const LOOP_MS = 7200

// One full dictation cycle expressed as a pure function of elapsed time, so the
// loop can be paused/resumed and stays in sync with the waveform.
function viewAt(totalElapsed: number, examples: SceneExample[]): SceneView {
  const index = Math.floor(totalElapsed / LOOP_MS) % examples.length
  const t = totalElapsed % LOOP_MS
  const { said, writes } = examples[index]

  if (t < 1900) {
    const p = Math.min(1, t / 1700)
    return {
      phase: 'listening',
      capsuleText: said.slice(0, Math.ceil(said.length * p)),
      output: '',
      injected: false,
      index,
    }
  }
  if (t < 2900) {
    return { phase: 'listening', capsuleText: said, output: '', injected: false, index }
  }
  if (t < 3400) {
    return { phase: 'transcribing', capsuleText: '', output: '', injected: false, index }
  }
  if (t < 4200) {
    return { phase: 'refining', capsuleText: '', output: '', injected: false, index }
  }
  if (t < 5300) {
    const p = Math.min(1, (t - 4200) / 950)
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
      setView(viewAt(5000, examples))
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
