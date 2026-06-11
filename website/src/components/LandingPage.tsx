import { apps, openSourceBenefits } from './content'
import { DashboardWindow } from './DashboardWindow'
import { Features } from './Features'
import { DotFieldBackground } from './DotFieldBackground'

const downloadUrl = 'https://github.com/BubblePtr/Voily/releases/latest'
const githubUrl = 'https://github.com/BubblePtr/Voily'

function GitHubIcon() {
  return (
    <svg aria-hidden="true" focusable="false" viewBox="0 0 24 24">
      <path
        d="M12 .5C5.65.5.9 5.24.9 11.46c0 4.84 3.13 8.94 7.47 10.39.55.1.75-.23.75-.52v-1.96c-3.04.65-3.68-1.28-3.68-1.28-.5-1.23-1.21-1.56-1.21-1.56-.99-.66.07-.65.07-.65 1.09.08 1.67 1.1 1.67 1.1.97 1.63 2.55 1.16 3.17.89.1-.69.38-1.16.69-1.43-2.43-.27-4.99-1.19-4.99-5.31 0-1.17.43-2.13 1.12-2.88-.11-.27-.49-1.37.11-2.84 0 0 .91-.29 3 1.1A10.5 10.5 0 0 1 12 6.14c.93 0 1.86.12 2.73.36 2.08-1.39 2.99-1.1 2.99-1.1.6 1.47.22 2.57.11 2.84.7.75 1.12 1.71 1.12 2.88 0 4.13-2.56 5.04-5 5.31.39.33.74.98.74 1.98v2.94c0 .29.2.63.76.52 4.34-1.45 7.46-5.55 7.46-10.39C23.1 5.24 18.35.5 12 .5Z"
        fill="currentColor"
      />
    </svg>
  )
}

export function LandingPage() {
  return (
    <main className="page">
      <header className="site-header">
        <a className="brand" href="#top" aria-label="Voily home">
          <img src="/voily-icon.png" alt="" />
          <span>Voily</span>
        </a>
        <div className="header-actions">
          <a
            aria-label="View Voily on GitHub"
            className="github-link"
            href={githubUrl}
            title="GitHub"
          >
            <GitHubIcon />
          </a>
        </div>
      </header>

      <section className="hero" id="top" aria-labelledby="hero-title">
        <DotFieldBackground />
        <div className="hero-copy">
          <h1 id="hero-title" aria-label="Just speak. We'll handle the rest.">
            <span>Just speak.</span>
            <span>We'll handle the rest.</span>
          </h1>
          <p>From raw voice to refined text, right where your cursor is.</p>
          <a className="primary-cta" href={downloadUrl}>
            Download for macOS
          </a>
          <span className="hero-meta">
            macOS 14+ · Apple Silicon · Open Source
          </span>
        </div>
      </section>

      <section className="showcase" id="showcase" aria-label="Voily app">
        <div className="showcase-frame">
          <DashboardWindow />
        </div>
        <a className="scroll-cue" href="#features" aria-label="Scroll to features">
          <span />
        </a>
      </section>

      <Features />

      <section className="works-section" aria-label="Works everywhere">
        <p>If you can type there, you can speak there.</p>
        <div className="app-marquee" aria-label="Supported apps">
          <div className="app-strip">
            {[0, 1].map((groupIndex) => (
              <div
                aria-hidden={groupIndex === 1}
                className="app-strip-group"
                key={groupIndex}
              >
                {apps.map((app) => (
                  <span className="app-pill" key={`${groupIndex}-${app.name}`}>
                    <img
                      alt=""
                      aria-hidden="true"
                      className="app-icon"
                      src={app.iconPath}
                    />
                    <span>{app.name}</span>
                  </span>
                ))}
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="open-source-section" aria-labelledby="open-source-title">
        <div className="open-source-copy">
          <span className="section-kicker">Open Source</span>
          <h2 id="open-source-title">Open source, made for your Mac.</h2>
          <p>
            Voily is open source. Inspect the code, shape the roadmap, and help
            make voice-to-text feel native everywhere you type.
          </p>
          <a className="star-cta" href={githubUrl}>
            <GitHubIcon />
            <span>Star on GitHub</span>
          </a>
        </div>
        <div className="open-source-grid">
          {openSourceBenefits.map((benefit) => (
            <article className="open-source-card" key={benefit.title}>
              <h3>{benefit.title}</h3>
              <p>{benefit.copy}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="final-cta" aria-labelledby="final-cta-title">
        <h2 id="final-cta-title">Stop typing. Start thinking.</h2>
        <a className="primary-cta" href={downloadUrl}>
          Download for macOS
        </a>
        <span className="hero-meta">
          macOS 14+ · Apple Silicon · Open Source
        </span>
      </section>

      <footer className="site-footer">
        <nav aria-label="Footer links">
          <a href={githubUrl}>GitHub</a>
        </nav>
        <span>© 2026 Voily</span>
      </footer>
    </main>
  )
}
