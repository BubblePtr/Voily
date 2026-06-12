import type { ReactNode } from 'react'

// Reusable macOS window chrome. Traffic lights + optional toolbar, then a body
// slot. Used both for the Voily dashboard recreation and the target-app scenes.

type AppWindowProps = {
  children: ReactNode
  className?: string
  toolbar?: ReactNode
  flush?: boolean
}

export function TrafficLights() {
  return (
    <span className="win-lights" aria-hidden="true">
      <span className="win-light win-close" />
      <span className="win-light win-min" />
      <span className="win-light win-zoom" />
    </span>
  )
}

export function AppWindow({ children, className, toolbar, flush }: AppWindowProps) {
  return (
    <div className={`app-window${className ? ` ${className}` : ''}`}>
      {toolbar !== undefined ? (
        <div className="win-toolbar">
          <TrafficLights />
          {toolbar}
        </div>
      ) : null}
      <div className={`win-body${flush ? ' is-flush' : ''}`}>{children}</div>
    </div>
  )
}
