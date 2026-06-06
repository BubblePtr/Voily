import { useEffect, useRef } from 'react'

const GRID_SIZE = 20
const SQUARE_SIZE = 7.5
const RIPPLE_RADIUS = 310
const MAX_DEVICE_PIXEL_RATIO = 2

type PointerState = {
  active: boolean
  lastMove: number
  x: number
  y: number
}

export function DotFieldBackground() {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = canvasRef.current
    const context = canvas?.getContext('2d')

    if (!canvas || !context) return

    const hero = canvas.closest<HTMLElement>('.hero')
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)')
    const pointer: PointerState = {
      active: false,
      lastMove: 0,
      x: 0,
      y: 0
    }

    let animationFrame: number | null = null
    let height = 0
    let width = 0

    const resize = () => {
      const rect = canvas.getBoundingClientRect()
      const ratio = Math.min(window.devicePixelRatio || 1, MAX_DEVICE_PIXEL_RATIO)

      width = rect.width
      height = rect.height
      canvas.width = Math.max(1, Math.floor(width * ratio))
      canvas.height = Math.max(1, Math.floor(height * ratio))
      context.setTransform(ratio, 0, 0, ratio, 0, 0)
    }

    const getCanvasEdgeAlpha = (x: number, y: number) => {
      const edgeDistance = Math.min(
        x / 52,
        (width - x) / 52,
        y / 52,
        (height - y) / 52,
        1
      )

      return smoothStep(edgeDistance)
    }

    const hashPoint = (x: number, y: number) => {
      const value = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453
      return value - Math.floor(value)
    }

    const smoothStep = (value: number) => {
      const t = Math.max(0, Math.min(1, value))
      return t * t * (3 - 2 * t)
    }

    const getOrganicFalloff = (x: number, y: number, time: number) => {
      const dx = x - pointer.x
      const dy = y - pointer.y
      const distance = Math.hypot(dx, dy)
      const angle = distance === 0 ? 0 : Math.atan2(dy, dx)
      const angleNoise =
        Math.sin(angle * 2.1 + time / 780) * 0.16 +
        Math.sin(angle * 5.3 - time / 1040) * 0.11 +
        Math.sin(angle * 9.7 + 1.8) * 0.08
      const cellX = Math.floor(x / GRID_SIZE)
      const cellY = Math.floor(y / GRID_SIZE)
      const cellNoise = hashPoint(cellX * 23.31, cellY * 41.73)
      const radius = RIPPLE_RADIUS * (0.82 + angleNoise + cellNoise * 0.22)
      const normalizedDistance = distance / Math.max(1, radius)

      if (normalizedDistance >= 1) return 0

      const falloff = smoothStep(1 - normalizedDistance)
      const edgeBreakup = hashPoint(cellX * 13.17 + Math.floor(time / 260), cellY * 29.91)
      const edgeBias = Math.max(0, normalizedDistance - 0.48) / 0.52

      if (edgeBias > 0.16 && edgeBreakup < edgeBias * 0.42) return 0

      const texture = 0.58 + cellNoise * 0.42
      return falloff * texture
    }

    const drawSquare = (
      x: number,
      y: number,
      time: number,
      interactionStrength: number
    ) => {
      if (interactionStrength <= 0) return

      const baseAlpha = getCanvasEdgeAlpha(x, y)
      if (baseAlpha <= 0.01) return

      const dx = x - pointer.x
      const dy = y - pointer.y
      const distance = Math.hypot(dx, dy)
      const rippleFalloff = getOrganicFalloff(x, y, time)
      const influence = rippleFalloff * interactionStrength
      if (influence <= 0.01) return

      const angle = distance === 0 ? 0 : Math.atan2(dy, dx)
      const wave = Math.sin(distance / 17 - time / 145)
      const offset = reducedMotion.matches ? 0 : wave * influence * 7
      const squareX = x + Math.cos(angle) * offset
      const squareY = y + Math.sin(angle) * offset
      const size = SQUARE_SIZE + influence * 3.4
      const alpha = baseAlpha * influence * 0.95

      context.fillStyle = `rgba(70, 123, 255, ${alpha})`
      context.fillRect(squareX - size / 2, squareY - size / 2, size, size)
    }

    const draw = (time: number) => {
      context.clearRect(0, 0, width, height)

      const isFreshPointer = pointer.active && time - pointer.lastMove < 2200
      const interactionStrength = isFreshPointer
        ? Math.max(0, 1 - (time - pointer.lastMove) / 2200)
        : 0

      if (interactionStrength <= 0) {
        animationFrame = null
        return
      }

      for (let y = 0; y <= height + GRID_SIZE; y += GRID_SIZE) {
        for (let x = 0; x <= width + GRID_SIZE; x += GRID_SIZE) {
          drawSquare(x, y, time, interactionStrength)
        }
      }

      animationFrame = window.requestAnimationFrame(draw)
    }

    const startAnimation = () => {
      if (animationFrame !== null) return

      animationFrame = window.requestAnimationFrame(draw)
    }

    const stopAnimation = () => {
      if (animationFrame === null) return

      window.cancelAnimationFrame(animationFrame)
      animationFrame = null
    }

    const handlePointerMove = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect()
      pointer.x = event.clientX - rect.left
      pointer.y = event.clientY - rect.top
      pointer.active =
        pointer.x >= 0 &&
        pointer.x <= rect.width &&
        pointer.y >= 0 &&
        pointer.y <= rect.height
      pointer.lastMove = performance.now()

      if (pointer.active) {
        startAnimation()
      }
    }

    const handlePointerLeave = () => {
      pointer.active = false
    }

    resize()

    window.addEventListener('resize', resize)
    hero?.addEventListener('pointermove', handlePointerMove, { passive: true })
    hero?.addEventListener('pointerleave', handlePointerLeave, { passive: true })

    return () => {
      stopAnimation()
      window.removeEventListener('resize', resize)
      hero?.removeEventListener('pointermove', handlePointerMove)
      hero?.removeEventListener('pointerleave', handlePointerLeave)
    }
  }, [])

  return (
    <canvas
      aria-hidden="true"
      className="dot-field-background"
      ref={canvasRef}
    />
  )
}
