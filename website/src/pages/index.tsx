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
            href="/DesktopPet/docs/architecture">
            READ THE DOCS
          </a>
        </div>
      </div>
    </header>
  );
}

const FeatureList = [
  {
    title: '🧠 Reinforcement Learning',
    description: (
      <>
        Byte's autonomous actions are driven by a native Swift Q-Learning engine. 
        He learns your routine based on environmental states (Time, Active Apps, Attention) and user feedback.
      </>
    ),
  },
  {
    title: '🗣️ Local Voice I/O',
    description: (
      <>
        Completely private and offline voice parsing using <code>faster-whisper</code> for Speech-to-Text 
        and <code>Kokoro</code> for hyper-realistic Text-to-Speech.
      </>
    ),
  },
  {
    title: '🎮 3D Physics & Awareness',
    description: (
      <>
        Built on SceneKit with a custom physics engine. Byte can walk on your Dock, 
        interact with active windows using macOS Accessibility APIs, and react to local weather.
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
