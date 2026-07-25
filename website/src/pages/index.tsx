import React, { useState } from 'react';
import Layout from '@theme/Layout';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';

function HomepageHeader() {
  const { siteConfig } = useDocusaurusContext();
  const [copied, setCopied] = useState(false);

  const copyCommand = () => {
    navigator.clipboard.writeText('./start.sh');
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <header style={{
      padding: '5rem 1rem 4rem 1rem',
      textAlign: 'center',
      background: 'linear-gradient(180deg, rgba(20, 20, 30, 0.95) 0%, rgba(10, 10, 15, 0.98) 100%)',
      color: '#ffffff',
      borderBottom: '1px solid rgba(255, 255, 255, 0.1)',
      position: 'relative'
    }}>
      <div style={{ maxWidth: '900px', margin: '0 auto' }}>
        <div style={{ marginBottom: '1.5rem' }}>
          <img 
            src="/img/byte_logo.png" 
            alt="Byte Cat Paw Logo" 
            style={{ 
              width: '140px', 
              height: '140px', 
              borderRadius: '28px',
              boxShadow: '0 0 35px rgba(0, 229, 255, 0.3)',
              border: '2px solid rgba(0, 229, 255, 0.5)'
            }} 
          />
        </div>

        <h1 style={{ 
          fontSize: '3rem', 
          fontWeight: 800, 
          letterSpacing: '-0.03em', 
          marginBottom: '1rem',
          background: 'linear-gradient(90deg, #ffffff 0%, #00e5ff 100%)',
          WebkitBackgroundClip: 'text',
          WebkitTextFillColor: 'transparent'
        }}>
          🐾 Byte: Intelligent 3D Desktop Pet
        </h1>

        <p style={{ 
          fontSize: '1.35rem', 
          color: '#a0aec0', 
          maxWidth: '700px', 
          margin: '0 auto 2rem auto',
          lineHeight: '1.6'
        }}>
          An empathetic, autonomous, and 100% offline 3D desktop pet companion for macOS—powered by Apple Silicon MLX GPU fine-tuning and local speech AI.
        </p>

        {/* Tech Badges */}
        <div style={{ display: 'flex', justifyContent: 'center', gap: '0.75rem', flexWrap: 'wrap', marginBottom: '2rem' }}>
          <span style={{ background: 'rgba(0, 229, 255, 0.15)', color: '#00e5ff', border: '1px solid rgba(0, 229, 255, 0.4)', padding: '0.4rem 1rem', borderRadius: '20px', fontSize: '0.85rem', fontWeight: 600 }}>macOS 14.0+</span>
          <span style={{ background: 'rgba(255, 149, 0, 0.15)', color: '#ff9500', border: '1px solid rgba(255, 149, 0, 0.4)', padding: '0.4rem 1rem', borderRadius: '20px', fontSize: '0.85rem', fontWeight: 600 }}>Swift 5.9 / SceneKit</span>
          <span style={{ background: 'rgba(52, 199, 89, 0.15)', color: '#34c759', border: '1px solid rgba(52, 199, 89, 0.4)', padding: '0.4rem 1rem', borderRadius: '20px', fontSize: '0.85rem', fontWeight: 600 }}>Apple MLX Metal GPU</span>
          <span style={{ background: 'rgba(175, 82, 222, 0.15)', color: '#af52de', border: '1px solid rgba(175, 82, 222, 0.4)', padding: '0.4rem 1rem', borderRadius: '20px', fontSize: '0.85rem', fontWeight: 600 }}>Ollama byte-llm</span>
          <span style={{ background: 'rgba(255, 255, 255, 0.15)', color: '#ffffff', border: '1px solid rgba(255, 255, 255, 0.3)', padding: '0.4rem 1rem', borderRadius: '20px', fontSize: '0.85rem', fontWeight: 600 }}>100% Offline & Private</span>
        </div>

        {/* Quick Launch Code Snippet */}
        <div style={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: '1rem',
          background: '#0d1117',
          border: '1px solid rgba(255, 255, 255, 0.15)',
          borderRadius: '12px',
          padding: '0.75rem 1.25rem',
          marginBottom: '2.5rem',
          fontFamily: 'monospace',
          color: '#58a6ff'
        }}>
          <span>$ chmod +x start.sh && ./start.sh</span>
          <button 
            onClick={copyCommand}
            style={{
              background: copied ? '#238636' : '#21262d',
              color: '#ffffff',
              border: 'none',
              borderRadius: '6px',
              padding: '0.4rem 0.8rem',
              cursor: 'pointer',
              fontSize: '0.8rem',
              fontWeight: 600
            }}>
            {copied ? '✓ Copied' : 'Copy'}
          </button>
        </div>

        {/* Action CTA Buttons */}
        <div style={{ display: 'flex', justifyContent: 'center', gap: '1rem', flexWrap: 'wrap' }}>
          <a
            className="button button--primary button--lg"
            href="/docs/architecture"
            style={{ background: '#00e5ff', color: '#000000', border: 'none', fontWeight: 700 }}>
            Architecture Overview
          </a>
          <a
            className="button button--secondary button--lg"
            href="/docs/empathy-ml-pipeline"
            style={{ background: 'rgba(255, 255, 255, 0.1)', color: '#ffffff', border: '1px solid rgba(255, 255, 255, 0.3)', fontWeight: 600 }}>
            Empathy ML Pipeline
          </a>
          <a
            className="button button--outline button--lg"
            href="/docs/installation-guide"
            style={{ color: '#00e5ff', borderColor: '#00e5ff', fontWeight: 600 }}>
            Quickstart Guide
          </a>
        </div>
      </div>
    </header>
  );
}

export default function Home(): JSX.Element {
  const { siteConfig } = useDocusaurusContext();

  return (
    <Layout
      title={`${siteConfig.title} - Intelligent 3D Desktop Pet for macOS`}
      description="Documentation and Architecture Guide for Byte: Empathetic 3D Desktop Pet for macOS">
      <HomepageHeader />
      <main style={{ background: '#0a0a0f', color: '#ffffff', padding: '4rem 1rem' }}>
        
        {/* System Architecture Showcase */}
        <section style={{ maxWidth: '1100px', margin: '0 auto 6rem auto' }}>
          <div style={{ textAlign: 'center', marginBottom: '3rem' }}>
            <h2 style={{ fontSize: '2.25rem', fontWeight: 700, color: '#ffffff', marginBottom: '0.75rem' }}>
              📐 System Architecture & Subsystems
            </h2>
            <p style={{ color: '#a0aec0', fontSize: '1.15rem', maxWidth: '750px', margin: '0 auto' }}>
              A hybrid four-layer system combining native macOS Accessibility sensors, local speech AI, SceneKit 3D rendering, and Ollama LLM intent deduction.
            </p>
          </div>

          <div style={{ 
            background: '#12131a', 
            borderRadius: '16px', 
            padding: '2rem', 
            border: '1px solid rgba(0, 229, 255, 0.2)',
            boxShadow: '0 10px 30px rgba(0, 0, 0, 0.5)',
            textAlign: 'center',
            marginBottom: '3rem'
          }}>
            <img 
              src="/img/byte_architecture_sketch.png" 
              alt="Byte System Architecture Sketch Diagram" 
              style={{ width: '100%', maxWidth: '850px', height: 'auto', borderRadius: '12px' }} 
            />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '1.5rem' }}>
            <div style={{ background: '#14151f', padding: '1.5rem', borderRadius: '12px', border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <h3 style={{ color: '#00e5ff', fontSize: '1.2rem' }}>🎤 Whisper STT</h3>
              <p style={{ color: '#a0aec0', fontSize: '0.95rem' }}>Local speech recognition running on Port 9000. 100% offline voice input.</p>
            </div>
            <div style={{ background: '#14151f', padding: '1.5rem', borderRadius: '12px', border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <h3 style={{ color: '#ff9500', fontSize: '1.2rem' }}>🧠 Ollama `byte-llm`</h3>
              <p style={{ color: '#a0aec0', fontSize: '0.95rem' }}>Fine-tuned Llama 3.2 model predicting `[ACTION: ...] [EMOTION: ...]` tags on Port 11434.</p>
            </div>
            <div style={{ background: '#14151f', padding: '1.5rem', borderRadius: '12px', border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <h3 style={{ color: '#34c759', fontSize: '1.2rem' }}>🎮 SceneKit 3D Engine</h3>
              <p style={{ color: '#a0aec0', fontSize: '0.95rem' }}>Swift transparent overlay with window gravity, drag throw physics, and surface collisions.</p>
            </div>
            <div style={{ background: '#14151f', padding: '1.5rem', borderRadius: '12px', border: '1px solid rgba(255, 255, 255, 0.08)' }}>
              <h3 style={{ color: '#af52de', fontSize: '1.2rem' }}>🔊 Kokoro TTS</h3>
              <p style={{ color: '#a0aec0', fontSize: '0.95rem' }}>Hyper-realistic speech synthesis on Port 8000 streaming voice directly to Mac speakers.</p>
            </div>
          </div>
        </section>

        {/* Empathy Machine Learning Section */}
        <section style={{ maxWidth: '1100px', margin: '0 auto 6rem auto' }}>
          <div style={{ textAlign: 'center', marginBottom: '3rem' }}>
            <h2 style={{ fontSize: '2.25rem', fontWeight: 700, color: '#ffffff', marginBottom: '0.75rem' }}>
              🔬 Empathy AI & ML Fine-Tuning Pipeline
            </h2>
            <p style={{ color: '#a0aec0', fontSize: '1.15rem', maxWidth: '750px', margin: '0 auto' }}>
              Fine-tuned on Meta AI's EmpatheticDialogues dataset using Apple Silicon MLX GPU acceleration for natural emotional companionship.
            </p>
          </div>

          <div style={{ 
            background: '#12131a', 
            borderRadius: '16px', 
            padding: '2rem', 
            border: '1px solid rgba(175, 82, 222, 0.3)',
            boxShadow: '0 10px 30px rgba(0, 0, 0, 0.5)',
            textAlign: 'center',
            marginBottom: '3rem'
          }}>
            <img 
              src="/img/byte_ml_pipeline_sketch.png" 
              alt="Byte Machine Learning Pipeline Sketch Diagram" 
              style={{ width: '100%', maxWidth: '850px', height: 'auto', borderRadius: '12px' }} 
            />
          </div>

          {/* Metric Counter Cards */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '1.5rem', textAlign: 'center' }}>
            <div style={{ background: '#14151f', padding: '1.5rem', borderRadius: '12px', border: '1px solid rgba(0, 229, 255, 0.2)' }}>
              <div style={{ fontSize: '2.5rem', fontWeight: 800, color: '#00e5ff' }}>45,328</div>
              <div style={{ color: '#a0aec0', fontSize: '0.9rem', marginTop: '0.25rem' }}>Empathetic Dialogue Samples</div>
            </div>
            <div style={{ background: '#14151f', padding: '1.5rem', borderRadius: '12px', border: '1px solid rgba(52, 199, 89, 0.2)' }}>
              <div style={{ fontSize: '2.5rem', fontWeight: 800, color: '#34c759' }}>&gt;50%</div>
              <div style={{ color: '#a0aec0', fontSize: '0.9rem', marginTop: '0.25rem' }}>Validation Loss Drop (4.48 ➔ 2.15)</div>
            </div>
            <div style={{ background: '#14151f', padding: '1.5rem', borderRadius: '12px', border: '1px solid rgba(255, 149, 0, 0.2)' }}>
              <div style={{ fontSize: '2.5rem', fontWeight: 800, color: '#ff9500' }}>30+</div>
              <div style={{ color: '#a0aec0', fontSize: '0.9rem', marginTop: '0.25rem' }}>Emotion-to-3D Action Mappings</div>
            </div>
            <div style={{ background: '#14151f', padding: '1.5rem', borderRadius: '12px', border: '1px solid rgba(175, 82, 222, 0.2)' }}>
              <div style={{ fontSize: '2.5rem', fontWeight: 800, color: '#af52de' }}>1.4 GB</div>
              <div style={{ color: '#a0aec0', fontSize: '0.9rem', marginTop: '0.25rem' }}>Peak RAM GPU Footprint</div>
            </div>
          </div>
        </section>

      </main>
    </Layout>
  );
}
