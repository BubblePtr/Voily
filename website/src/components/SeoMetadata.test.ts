import { existsSync, readFileSync } from 'node:fs'
import { describe, expect, test } from 'bun:test'

const indexHtml = readFileSync(new URL('../../index.html', import.meta.url), 'utf8')
const ogImageUrl = new URL('../../public/og-image.png', import.meta.url)
const siteUrl = 'https://voily.pages.dev/'
const socialImageUrl = `${siteUrl}og-image.png`

function metaContent(property: string) {
  const escapedProperty = property.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const pattern = new RegExp(
    `<meta\\s+(?:property|name)="${escapedProperty}"\\s+content="([^"]+)"\\s*/?>`,
  )

  return indexHtml.match(pattern)?.[1]
}

function linkHref(rel: string) {
  const escapedRel = rel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const pattern = new RegExp(`<link\\s+rel="${escapedRel}"\\s+href="([^"]+)"\\s*/?>`)

  return indexHtml.match(pattern)?.[1]
}

function readPngDimensions(buffer: Buffer) {
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
  }
}

describe('SEO metadata', () => {
  test('exposes a social preview image for Open Graph and Twitter cards', () => {
    expect(linkHref('canonical')).toBe(siteUrl)
    expect(metaContent('og:url')).toBe(siteUrl)
    expect(metaContent('og:image')).toBe(socialImageUrl)
    expect(metaContent('og:image:secure_url')).toBe(socialImageUrl)
    expect(metaContent('twitter:image')).toBe(socialImageUrl)
    expect(metaContent('og:image:width')).toBe('1200')
    expect(metaContent('og:image:height')).toBe('630')
  })

  test('ships the social preview image as a 1200x630 PNG source asset', () => {
    expect(existsSync(ogImageUrl)).toBe(true)

    const buffer = readFileSync(ogImageUrl)
    expect(buffer.subarray(1, 4).toString('ascii')).toBe('PNG')
    expect(readPngDimensions(buffer)).toEqual({ width: 1200, height: 630 })
  })
})
