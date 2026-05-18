"use client";

import { useState, useEffect, useRef } from "react";
import { toPng } from "html-to-image";

// ── Canvas (iPhone 6.9", largest required) ──────────────────────────────
const W = 1320;
const H = 2868;

// ── iPhone mockup measurements (matches included mockup.png) ────────────
const MK_W = 1022;
const MK_H = 2082;
const MK_RATIO = MK_W / MK_H;
const SC_L = (52 / MK_W) * 100;
const SC_T = (46 / MK_H) * 100;
const SC_W = (918 / MK_W) * 100;
const SC_H = (1990 / MK_H) * 100;
const SC_RX = (126 / 918) * 100;
const SC_RY = (126 / 1990) * 100;

// ── Apple required export sizes ─────────────────────────────────────────
const IPHONE_SIZES = [
  { label: '6.9"', w: 1320, h: 2868 },
  { label: '6.5"', w: 1284, h: 2778 },
  { label: '6.3"', w: 1206, h: 2622 },
  { label: '6.1"', w: 1125, h: 2436 },
] as const;

// ── Theme: dark / developer-tool moody with App Store blue accent ───────
const THEME = {
  bg1: "linear-gradient(160deg, #060812 0%, #0c1230 45%, #18214a 100%)",
  bg2: "linear-gradient(210deg, #08091c 0%, #131a3c 55%, #2a1d52 100%)",
  fg: "#F5F7FB",
  accent: "#0A84FF",
  accent2: "#7C5CFF",
  muted: "rgba(245,247,251,0.62)",
  card: "rgba(255,255,255,0.04)",
  cardBorder: "rgba(255,255,255,0.08)",
} as const;

// ── Image preload (mandatory for html-to-image reliability) ─────────────
const IMAGE_PATHS = [
  "/mockup.png",
  "/app-icon.png",
  "/screenshots/shelf.png",
  "/screenshots/share.png",
  "/screenshots/qr.png",
];

const imageCache: Record<string, string> = {};

async function preloadAllImages() {
  await Promise.all(
    IMAGE_PATHS.map(async (path) => {
      try {
        const resp = await fetch(path);
        if (!resp.ok) {
          imageCache[path] = path;
          return;
        }
        const blob = await resp.blob();
        const dataUrl = await new Promise<string>((resolve) => {
          const reader = new FileReader();
          reader.onloadend = () => resolve(reader.result as string);
          reader.readAsDataURL(blob);
        });
        imageCache[path] = dataUrl;
      } catch {
        imageCache[path] = path;
      }
    })
  );
}

function img(path: string): string {
  return imageCache[path] || path;
}

// ── Width formulas (canvas-relative) ────────────────────────────────────
function phoneW(cW: number, cH: number, clamp = 0.84) {
  return Math.min(clamp, 0.72 * (cH / cW) * MK_RATIO);
}

// ── Phone frame (iPhone mockup PNG + clipped screen) ────────────────────
function Phone({
  src,
  alt,
  style,
  objectFit = "cover",
  objectPosition = "top",
  screenBackground,
}: {
  src: string;
  alt: string;
  style?: React.CSSProperties;
  objectFit?: "cover" | "contain";
  objectPosition?: string;
  screenBackground?: string;
}) {
  return (
    <div
      style={{ position: "relative", aspectRatio: `${MK_W}/${MK_H}`, ...style }}
    >
      <img
        src={img("/mockup.png")}
        alt=""
        style={{ display: "block", width: "100%", height: "100%" }}
        draggable={false}
      />
      <div
        style={{
          position: "absolute",
          zIndex: 10,
          overflow: "hidden",
          left: `${SC_L}%`,
          top: `${SC_T}%`,
          width: `${SC_W}%`,
          height: `${SC_H}%`,
          borderRadius: `${SC_RX}% / ${SC_RY}%`,
          background: screenBackground,
        }}
      >
        <img
          src={src}
          alt={alt}
          style={{
            display: "block",
            width: "100%",
            height: "100%",
            objectFit,
            objectPosition,
          }}
          draggable={false}
        />
      </div>
    </div>
  );
}

// ── Decorative glow (soft radial behind the device) ─────────────────────
function Glow({
  color,
  x,
  y,
  size,
  opacity = 0.55,
}: {
  color: string;
  x: string;
  y: string;
  size: string;
  opacity?: number;
}) {
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: size,
        height: size,
        transform: "translate(-50%, -50%)",
        background: `radial-gradient(circle, ${color} 0%, ${color}00 65%)`,
        opacity,
        filter: "blur(2px)",
        pointerEvents: "none",
        zIndex: 1,
      }}
    />
  );
}

// ── Slide 1 — Hero: "Every promo code, in one place." ───────────────────
function Slide1({ cW, cH }: { cW: number; cH: number }) {
  const fw = phoneW(cW, cH) * 100;
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        position: "relative",
        overflow: "hidden",
        background: THEME.bg1,
      }}
    >
      <Glow color={THEME.accent} x="50%" y="78%" size={`${cW * 1.2}px`} opacity={0.5} />
      <Glow color={THEME.accent2} x="85%" y="20%" size={`${cW * 0.7}px`} opacity={0.35} />

      <div
        style={{
          position: "absolute",
          top: cH * 0.07,
          left: cW * 0.07,
          right: cW * 0.07,
          zIndex: 5,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: cW * 0.022, marginBottom: cW * 0.04 }}>
          <img
            src={img("/app-icon.png")}
            alt=""
            style={{
              width: cW * 0.075,
              height: cW * 0.075,
              borderRadius: cW * 0.017,
              boxShadow: `0 ${cW * 0.006}px ${cW * 0.02}px rgba(0,0,0,0.4)`,
            }}
            draggable={false}
          />
          <div
            style={{
              fontSize: cW * 0.028,
              fontWeight: 600,
              letterSpacing: cW * 0.0012,
              color: THEME.accent,
              textTransform: "uppercase",
            }}
          >
            PromoKit
          </div>
        </div>
        <h2
          style={{
            fontSize: cW * 0.1,
            fontWeight: 700,
            color: THEME.fg,
            lineHeight: 0.95,
            letterSpacing: cW * -0.001,
            margin: 0,
          }}
        >
          Every promo code,
          <br />
          in one place.
        </h2>
        <p
          style={{
            fontSize: cW * 0.032,
            fontWeight: 400,
            color: THEME.muted,
            lineHeight: 1.3,
            marginTop: cW * 0.025,
            maxWidth: cW * 0.78,
          }}
        >
          Organize every app, every offer, every code.
        </p>
      </div>

      <Phone
        src={img("/screenshots/shelf.png")}
        alt="Shelf"
        style={{
          position: "absolute",
          bottom: 0,
          left: "50%",
          width: `${fw}%`,
          transform: "translateX(-50%) translateY(13%)",
          zIndex: 3,
          filter: `drop-shadow(0 ${cW * 0.025}px ${cW * 0.05}px rgba(0,0,0,0.55))`,
        }}
      />
    </div>
  );
}

// ── Slide 2 — Share: "Share the next code in one tap." ──────────────────
function Slide2({ cW, cH }: { cW: number; cH: number }) {
  const fw = phoneW(cW, cH, 0.82) * 100;
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        position: "relative",
        overflow: "hidden",
        background: THEME.bg2,
      }}
    >
      <Glow color={THEME.accent2} x="20%" y="30%" size={`${cW * 1.1}px`} opacity={0.45} />
      <Glow color={THEME.accent} x="80%" y="85%" size={`${cW * 0.9}px`} opacity={0.4} />

      <div
        style={{
          position: "absolute",
          top: cH * 0.07,
          left: cW * 0.07,
          right: cW * 0.07,
          zIndex: 5,
        }}
      >
        <div
          style={{
            fontSize: cW * 0.028,
            fontWeight: 600,
            letterSpacing: cW * 0.0012,
            color: THEME.accent,
            textTransform: "uppercase",
            marginBottom: cW * 0.03,
          }}
        >
          QR Share
        </div>
        <h2
          style={{
            fontSize: cW * 0.1,
            fontWeight: 700,
            color: THEME.fg,
            lineHeight: 0.95,
            letterSpacing: cW * -0.001,
            margin: 0,
          }}
        >
          Share a code
          <br />
          in one tap.
        </h2>
        <p
          style={{
            fontSize: cW * 0.032,
            fontWeight: 400,
            color: THEME.muted,
            lineHeight: 1.3,
            marginTop: cW * 0.025,
            maxWidth: cW * 0.78,
          }}
        >
          Link, QR, or copy — your call.
        </p>
      </div>

      <Phone
        src={img("/screenshots/share.png")}
        alt="Share"
        style={{
          position: "absolute",
          bottom: 0,
          left: "50%",
          width: `${fw}%`,
          transform: "translateX(-50%) translateY(15%) rotate(-3deg)",
          zIndex: 3,
          filter: `drop-shadow(0 ${cW * 0.03}px ${cW * 0.06}px rgba(0,0,0,0.6))`,
        }}
      />
    </div>
  );
}

// ── Slide 3 — QR card inside iPhone frame, presented as a modal sheet ──
// We inline the phone here (rather than reusing <Phone />) so the QR card
// can be sized to fill ~95% of screen width and we can add the sheet's
// drag handle — both fill the cream space that otherwise reads empty.
function Slide3({ cW, cH }: { cW: number; cH: number }) {
  const fw = phoneW(cW, cH) * 100;
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        position: "relative",
        overflow: "hidden",
        background: "linear-gradient(180deg, #060812 0%, #0c1230 50%, #1a2557 100%)",
      }}
    >
      <Glow color={THEME.accent} x="50%" y="65%" size={`${cW * 1.3}px`} opacity={0.45} />
      <Glow color={THEME.accent2} x="22%" y="22%" size={`${cW * 0.7}px`} opacity={0.32} />

      <div
        style={{
          position: "absolute",
          top: cH * 0.07,
          left: cW * 0.07,
          right: cW * 0.07,
          zIndex: 5,
        }}
      >
        <div
          style={{
            fontSize: cW * 0.028,
            fontWeight: 600,
            letterSpacing: cW * 0.0012,
            color: THEME.accent,
            textTransform: "uppercase",
            marginBottom: cW * 0.03,
          }}
        >
          Scan &amp; Redeem
        </div>
        <h2
          style={{
            fontSize: cW * 0.1,
            fontWeight: 700,
            color: THEME.fg,
            lineHeight: 0.95,
            letterSpacing: cW * -0.001,
            margin: 0,
          }}
        >
          Branded QR cards,
          <br />
          ready to scan.
        </h2>
        <p
          style={{
            fontSize: cW * 0.032,
            fontWeight: 400,
            color: THEME.muted,
            lineHeight: 1.3,
            marginTop: cW * 0.025,
            maxWidth: cW * 0.78,
          }}
        >
          One scan opens the App Store and applies the code.
        </p>
      </div>

      {/* Inline iPhone frame with custom screen content */}
      <div
        style={{
          position: "absolute",
          bottom: 0,
          left: "50%",
          width: `${fw}%`,
          aspectRatio: `${MK_W}/${MK_H}`,
          transform: "translateX(-50%) translateY(13%)",
          zIndex: 3,
          filter: `drop-shadow(0 ${cW * 0.025}px ${cW * 0.05}px rgba(0,0,0,0.55))`,
        }}
      >
        <img
          src={img("/mockup.png")}
          alt=""
          style={{ display: "block", width: "100%", height: "100%" }}
          draggable={false}
        />
        <div
          style={{
            position: "absolute",
            zIndex: 10,
            overflow: "hidden",
            left: `${SC_L}%`,
            top: `${SC_T}%`,
            width: `${SC_W}%`,
            height: `${SC_H}%`,
            borderRadius: `${SC_RX}% / ${SC_RY}%`,
            background: "#F0F2ED",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
          }}
        >
          {/* Drag handle — implies modal sheet, fills the cream top */}
          <div
            style={{
              marginTop: "5.5%",
              width: "11%",
              height: "0.55%",
              borderRadius: "999px",
              background: "rgba(60,60,67,0.35)",
            }}
          />

          {/* QR card — sized to fill width, slightly above center */}
          <div
            style={{
              flex: 1,
              width: "100%",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              paddingTop: "2%",
              paddingBottom: "8%",
            }}
          >
            <img
              src={img("/screenshots/qr.png")}
              alt="QR card"
              draggable={false}
              style={{
                width: "96%",
                height: "auto",
                display: "block",
              }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}

type SlideDef = {
  id: string;
  render: (p: { cW: number; cH: number }) => React.ReactElement;
};

const SLIDES: SlideDef[] = [
  { id: "hero", render: (p) => <Slide1 {...p} /> },
  { id: "share", render: (p) => <Slide2 {...p} /> },
  { id: "qr", render: (p) => <Slide3 {...p} /> },
];

// ── Preview card (auto-scales to fit grid cell) ─────────────────────────
function ScreenshotPreview({ slide }: { slide: SlideDef }) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(0.25);

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const obs = new ResizeObserver((entries) => {
      for (const e of entries) {
        setScale(e.contentRect.width / W);
      }
    });
    obs.observe(el);
    return () => obs.disconnect();
  }, []);

  return (
    <div
      ref={wrapRef}
      style={{
        width: "100%",
        aspectRatio: `${W}/${H}`,
        overflow: "hidden",
        borderRadius: 24,
        background: "#000",
        position: "relative",
        boxShadow: "0 6px 24px rgba(0,0,0,0.18)",
      }}
    >
      <div
        style={{
          width: W,
          height: H,
          transform: `scale(${scale})`,
          transformOrigin: "top left",
        }}
      >
        {slide.render({ cW: W, cH: H })}
      </div>
    </div>
  );
}

// ── Main page ───────────────────────────────────────────────────────────
export default function ScreenshotsPage() {
  const [ready, setReady] = useState(false);
  const [sizeIdx, setSizeIdx] = useState(0);
  const [exporting, setExporting] = useState<string | null>(null);
  // Refs indexed as [sizeIdx][slideIdx] — one render per (size × slide)
  const exportRefs = useRef<(HTMLDivElement | null)[][]>(
    IPHONE_SIZES.map(() => SLIDES.map(() => null))
  );

  useEffect(() => {
    preloadAllImages().then(() => setReady(true));
  }, []);

  const size = IPHONE_SIZES[sizeIdx];

  async function captureSlide(
    el: HTMLElement,
    w: number,
    h: number
  ): Promise<string> {
    el.style.left = "0px";
    el.style.opacity = "1";
    el.style.zIndex = "-1";
    const opts = { width: w, height: h, pixelRatio: 1, cacheBust: true };
    // Double-call: first warms fonts/images, second produces clean output
    await toPng(el, opts);
    const dataUrl = await toPng(el, opts);
    el.style.left = "-9999px";
    el.style.opacity = "";
    el.style.zIndex = "";
    return dataUrl;
  }

  async function downloadDataUrl(dataUrl: string, name: string) {
    const a = document.createElement("a");
    a.href = dataUrl;
    a.download = name;
    a.click();
  }

  async function exportOne(i: number) {
    const el = exportRefs.current[sizeIdx]?.[i];
    if (!el) return;
    setExporting(`${i + 1}/${SLIDES.length}`);
    try {
      const dataUrl = await captureSlide(el, size.w, size.h);
      const name = `${String(i + 1).padStart(2, "0")}-${SLIDES[i].id}-${size.w}x${size.h}.png`;
      await downloadDataUrl(dataUrl, name);
    } finally {
      setExporting(null);
    }
  }

  async function exportAll() {
    for (let i = 0; i < SLIDES.length; i++) {
      setExporting(`${i + 1}/${SLIDES.length}`);
      const el = exportRefs.current[sizeIdx]?.[i];
      if (!el) continue;
      const dataUrl = await captureSlide(el, size.w, size.h);
      const name = `${String(i + 1).padStart(2, "0")}-${SLIDES[i].id}-${size.w}x${size.h}.png`;
      await downloadDataUrl(dataUrl, name);
      await new Promise((r) => setTimeout(r, 300));
    }
    setExporting(null);
  }

  async function exportAllSizes() {
    for (let s = 0; s < IPHONE_SIZES.length; s++) {
      const sz = IPHONE_SIZES[s];
      for (let i = 0; i < SLIDES.length; i++) {
        setExporting(`${sz.label} ${i + 1}/${SLIDES.length}`);
        const el = exportRefs.current[s]?.[i];
        if (!el) continue;
        const dataUrl = await captureSlide(el, sz.w, sz.h);
        const name = `${String(i + 1).padStart(2, "0")}-${SLIDES[i].id}-${sz.w}x${sz.h}.png`;
        await downloadDataUrl(dataUrl, name);
        await new Promise((r) => setTimeout(r, 300));
      }
    }
    setExporting(null);
  }

  if (!ready) {
    return (
      <div style={{ padding: 40, fontSize: 14, color: "#374151" }}>
        Loading images…
      </div>
    );
  }

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#f3f4f6",
        position: "relative",
        overflowX: "hidden",
        color: "#111",
      }}
    >
      {/* Toolbar */}
      <div
        style={{
          position: "sticky",
          top: 0,
          zIndex: 50,
          background: "white",
          borderBottom: "1px solid #e5e7eb",
          display: "flex",
          alignItems: "center",
        }}
      >
        <div
          style={{
            flex: 1,
            display: "flex",
            alignItems: "center",
            gap: 12,
            padding: "10px 16px",
            overflowX: "auto",
            minWidth: 0,
          }}
        >
          <span style={{ fontWeight: 700, fontSize: 14, whiteSpace: "nowrap" }}>
            PromoKit · Screenshots
          </span>
          <span
            style={{
              fontSize: 11,
              color: "#6b7280",
              whiteSpace: "nowrap",
              padding: "3px 8px",
              borderRadius: 4,
              background: "#f3f4f6",
            }}
          >
            iPhone · Apple App Store
          </span>
          <select
            value={sizeIdx}
            onChange={(e) => setSizeIdx(Number(e.target.value))}
            style={{
              fontSize: 12,
              border: "1px solid #e5e7eb",
              borderRadius: 6,
              padding: "5px 10px",
            }}
          >
            {IPHONE_SIZES.map((s, i) => (
              <option key={i} value={i}>
                {s.label} — {s.w}×{s.h}
              </option>
            ))}
          </select>
        </div>
        <div
          style={{
            flexShrink: 0,
            padding: "10px 16px",
            borderLeft: "1px solid #e5e7eb",
            display: "flex",
            gap: 8,
          }}
        >
          <button
            onClick={exportAll}
            disabled={!!exporting}
            style={{
              padding: "7px 16px",
              background: exporting ? "#93c5fd" : "#2563eb",
              color: "white",
              border: "none",
              borderRadius: 8,
              fontSize: 12,
              fontWeight: 600,
              cursor: exporting ? "default" : "pointer",
              whiteSpace: "nowrap",
            }}
          >
            {exporting ? `Exporting… ${exporting}` : "Export current size"}
          </button>
          <button
            onClick={exportAllSizes}
            disabled={!!exporting}
            style={{
              padding: "7px 16px",
              background: "white",
              color: "#2563eb",
              border: "1px solid #2563eb",
              borderRadius: 8,
              fontSize: 12,
              fontWeight: 600,
              cursor: exporting ? "default" : "pointer",
              whiteSpace: "nowrap",
            }}
          >
            Export all 4 sizes
          </button>
        </div>
      </div>

      {/* Preview grid */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))",
          gap: 24,
          padding: 24,
        }}
      >
        {SLIDES.map((s, i) => (
          <div key={s.id}>
            <ScreenshotPreview slide={s} />
            <div
              style={{
                marginTop: 8,
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
              }}
            >
              <span style={{ fontSize: 12, color: "#6b7280" }}>
                {String(i + 1).padStart(2, "0")} · {s.id}
              </span>
              <button
                onClick={() => exportOne(i)}
                disabled={!!exporting}
                style={{
                  padding: "5px 12px",
                  fontSize: 11,
                  borderRadius: 6,
                  border: "1px solid #e5e7eb",
                  background: "white",
                  cursor: exporting ? "default" : "pointer",
                }}
              >
                Export this
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* Offscreen export renders — one per (size × slide), keyed for stable refs */}
      <div aria-hidden style={{ position: "absolute", left: -9999, top: 0 }}>
        {IPHONE_SIZES.map((sz, sIdx) =>
          SLIDES.map((s, i) => (
            <div
              key={`${sIdx}-${s.id}`}
              ref={(el) => {
                if (!exportRefs.current[sIdx]) exportRefs.current[sIdx] = [];
                exportRefs.current[sIdx][i] = el;
              }}
              style={{
                width: sz.w,
                height: sz.h,
                position: "absolute",
                left: -9999,
                top: 0,
              }}
            >
              {s.render({ cW: sz.w, cH: sz.h })}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
