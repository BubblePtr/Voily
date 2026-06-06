import { useEffect, useMemo, useState } from 'react'

import { demoExamples } from './content'

const LOOP_MS = 7500

function getStage(elapsed: number) {
  if (elapsed < 2000) return 'said'
  if (elapsed < 3000) return 'processing'
  if (elapsed < 5000) return 'writes'
  if (elapsed < 7000) return 'hold'
  return 'fade'
}

export function DemoCard() {
  const [time, setTime] = useState(0)

  useEffect(() => {
    const started = performance.now()
    const interval = window.setInterval(() => {
      setTime(performance.now() - started)
    }, 80)

    return () => window.clearInterval(interval)
  }, [])

  const exampleIndex = Math.floor(time / LOOP_MS) % demoExamples.length
  const elapsed = time % LOOP_MS
  const stage = getStage(elapsed)
  const example = demoExamples[exampleIndex]

  const typedSaid = useMemo(() => {
    if (stage !== 'said') return example.said

    const progress = Math.min(1, elapsed / 1900)
    return example.said.slice(0, Math.ceil(example.said.length * progress))
  }, [elapsed, example.said, stage])

  return (
    <div className={`demo-card demo-card-${stage}`}>
      <div className="demo-header">
        <span className="demo-app">{example.app}</span>
        <span className="demo-status">
          {stage === 'processing' ? 'Refining' : 'Voice to text'}
        </span>
      </div>

      <div className="demo-columns">
        <section className="demo-panel demo-panel-said" aria-label="Raw voice input">
          <span className="demo-label">You said</span>
          <p>{typedSaid}</p>
        </section>

        <div className="demo-process" aria-hidden="true">
          <span />
        </div>

        <section className="demo-panel demo-panel-writes" aria-label="Voily output">
          <span className="demo-label">Voily writes</span>
          <p>{example.writes}</p>
        </section>
      </div>

      <div className="demo-dots" aria-label={`Demo ${exampleIndex + 1} of ${demoExamples.length}`}>
        {demoExamples.map((item, index) => (
          <span
            className={index === exampleIndex ? 'is-active' : ''}
            key={item.app}
          />
        ))}
      </div>
    </div>
  )
}
