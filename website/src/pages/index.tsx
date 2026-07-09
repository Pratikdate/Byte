import React from 'react';
import Layout from '@theme/Layout';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Byte3DModel from '../components/Byte3DModel';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className="heroBanner">
      <div className="container">
        <h1 className="heroTitle">{siteConfig.title}</h1>
        <p className="heroSubtitle">{siteConfig.tagline}</p>
        <Byte3DModel />
        <div style={{ marginTop: '2rem' }}>
          <a
            className="button button--primary"
            href="/Byte/docs/architecture">
            READ THE DOCS
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
    title: '🗣️ On-Device LLM Integration',
    description: (
      <>
        Zero network dependency for ambient behaviors. Byte uses Apple's native <code>FoundationModels</code> framework 
        for fast, offline conversational flavor text that reacts to your environment.
      </>
    ),
  },
  {
    title: '🎮 3D Physics & Awareness',
    description: (
      <>
        Built on SceneKit with a custom physics engine. Byte can walk on your Dock, 
        interact with active windows using macOS Accessibility APIs, and react to local events.
      </>
    ),
  },
];

function Feature({title, description}) {
  return (
    <div className="featureCard">
      <h3>{title}</h3>
      <p>{description}</p>
    </div>
  );
}

export default function Home(): JSX.Element {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title={`${siteConfig.title} Docs`}
      description="Documentation for Byte: Intelligent 3D Desktop Pet">
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
