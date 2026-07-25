import React from 'react';
import Layout from '@theme/Layout';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Byte3DModel from '../components/Byte3DModel';

function HomepageHeader() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <header className="heroBanner">
      <div className="container">
        <h1 className="heroTitle">{siteConfig.title}</h1>
        <p className="heroSubtitle">{siteConfig.tagline}</p>
        <Byte3DModel />
        <div style={{ marginTop: '2rem', display: 'flex', justifyContent: 'center', gap: '1rem', flexWrap: 'wrap' }}>
          <a
            className="button button--primary button--lg"
            href="/docs/architecture">
            READ THE DOCS
          </a>
          <a
            className="button button--secondary button--lg"
            href="/docs/empathy-ml-pipeline">
            EMPATHY ML PIPELINE
          </a>
        </div>
      </div>
    </header>
  );
}

const FeatureList = [
  {
    title: '🧠 Utility AI & State Engine',
    description: (
      <>
        Byte's behavior emerges dynamically from internal state variables (energy, mood, curiosity). 
        The native Swift tick-based engine evaluates these states to choose actions organically.
      </>
    ),
  },
  {
    title: '🗣️ On-Device LLM & Empathy Fine-Tuning',
    description: (
      <>
        Zero network dependency for ambient behaviors. Fine-tuned on 45,000+ open-source empathetic dialogue pairs using Apple Silicon MLX GPU acceleration for local <code>byte-llm</code> context deduction.
      </>
    ),
  },
  {
    title: '🎮 3D Physics & Workspace Awareness',
    description: (
      <>
        Built on SceneKit with a custom physics engine. Byte walks along window frames and macOS Dock, 
        interacts with active windows via Accessibility APIs, and reacts to weather and ambient events.
      </>
    ),
  },
];

function Feature({ title, description }: { title: string; description: React.ReactNode }) {
  return (
    <div className="featureCard">
      <h3>{title}</h3>
      <p>{description}</p>
    </div>
  );
}

export default function Home(): JSX.Element {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout
      title={`${siteConfig.title} Docs`}
      description="Documentation for Byte: Intelligent 3D Desktop Pet for macOS">
      <HomepageHeader />
      <main>
        <section style={{ padding: '2rem 0 6rem 0' }}>
          <div className="container">
            <div className="featuresGrid">
              {FeatureList.map((props, idx) => (
                <Feature key={idx} {...props} />
              ))}
            </div>
          </div>
        </section>
      </main>
    </Layout>
  );
}
