// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const clamp = (value, min, max) => Math.min(Math.max(value, min), max)
const roundTo = (value, decimals = 4) => {
  const factor = Math.pow(10, decimals)
  return Math.round(value * factor) / factor
}
const padNumber = (value, width = 2) => String(value).padStart(width, "0")

const formatCooldownDuration = (remainingMs) => {
  const total = Math.max(0, Math.ceil(remainingMs))
  const minutes = Math.floor(total / 60000)
  const seconds = Math.floor((total % 60000) / 1000)
  const milliseconds = total % 1000
  return `${padNumber(minutes)}:${padNumber(seconds)}.${padNumber(milliseconds, 3)}`
}

const MAX_VOLUME_PERCENT_DEFAULT = 150
const BOOST_CAP = 1.5
const BUZZ_MODE_STORAGE_KEY = "soundboard:buzz-mode"
const BUZZ_MODE_CLASS = "buzz-mode"
const HONEY_DRIP_VAR_A = "--bb-honey-drips-a"
const HONEY_DRIP_VAR_B = "--bb-honey-drips-b"
const HONEY_PARALLAX_VAR_X = "--bb-honey-parallax-x"
const HONEY_PARALLAX_VAR_Y = "--bb-honey-parallax-y"
const HONEY_PARALLAX_MAX_X = 10
const HONEY_PARALLAX_MAX_Y = 8
const HONEY_SHEEN_ACTIVE_CLASS = "bb-honey-sheen-active"
const HONEY_SHEEN_WAVE_MS = 11000
const HONEY_SHEEN_MIN_DELAY_MS = 1800
const HONEY_SHEEN_MAX_DELAY_MS = 4200
const HONEY_PARALLAX_TARGET_SELECTOR = ".bb-sound-grid .bb-sound-card, #bb-queen-pick"
const QUEEN_PICK_DEFAULT_ROTATION_MS = 30000
const QUEEN_PICK_MIN_ROTATION_MS = 10000
const DESKTOP_NAV_COLLAPSED_CLASS = "desktop-nav-collapsed"
const CLIP_DURATION_CACHE_PREFIX = "soundboard:clip-duration:v1:"
const CLIP_DURATION_CACHE_TTL_MS = 1000 * 60 * 60 * 24 * 30
const clipDurationMemoryCache = new Map()
const buildUploadUrl = (filename) => `/uploads/${encodeURIComponent(filename)}`

const clearBuzzSyncFlag = (toggle) => {
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      toggle.removeAttribute("data-buzz-syncing")
    })
  })
}

const applyBuzzMode = (enabled, {suppressAnimation = false} = {}) => {
  applyRandomHoneyDrips()

  document.documentElement.classList.toggle(BUZZ_MODE_CLASS, enabled)
  if (document.body) {
    document.body.classList.toggle(BUZZ_MODE_CLASS, enabled)
  }

  resetAllHoneyParallax()

  if (!enabled) {
    stopHoneySheenWaves()
  } else {
    startHoneySheenWaves()
  }

  document.querySelectorAll("[data-buzz-toggle]").forEach((toggle) => {
    if (suppressAnimation) {
      toggle.setAttribute("data-buzz-syncing", "true")
    }

    if ("checked" in toggle) {
      toggle.checked = enabled
    }
    toggle.setAttribute("aria-checked", enabled ? "true" : "false")

    if (suppressAnimation) {
      clearBuzzSyncFlag(toggle)
    }
  })
}

const readBuzzModePreference = () => {
  try {
    return window.localStorage.getItem(BUZZ_MODE_STORAGE_KEY) === "on"
  } catch (_err) {
    return false
  }
}

const saveBuzzModePreference = (enabled) => {
  try {
    window.localStorage.setItem(BUZZ_MODE_STORAGE_KEY, enabled ? "on" : "off")
  } catch (_err) {}
}

const randomInRange = (min, max) => min + Math.random() * (max - min)

const buildRandomDripShadow = ({
  count,
  color,
  minAlpha,
  maxAlpha,
  minY,
  maxY,
  minSpread,
  maxSpread,
  jitterX
}) => {
  const [r, g, b] = color
  const minX = 4
  const maxX = 95
  const step = count > 1 ? (maxX - minX) / (count - 1) : 0
  const shadows = []

  for (let idx = 0; idx < count; idx += 1) {
    const baseX = minX + step * idx
    const x = roundTo(clamp(baseX + randomInRange(-jitterX, jitterX), minX, maxX), 2)
    const y = Math.round(randomInRange(minY, maxY))
    const spread = -Math.round(randomInRange(minSpread, maxSpread))
    const alpha = roundTo(randomInRange(minAlpha, maxAlpha), 2)
    shadows.push(`${x}vw ${y}px 0 ${spread}px rgba(${r}, ${g}, ${b}, ${alpha})`)
  }

  return shadows.join(", ")
}

const applyRandomHoneyDrips = () => {
  if (window.__bbHoneyDripsInitialized) {
    return
  }

  const rootStyle = document.documentElement?.style
  if (!rootStyle) {
    return
  }

  const primaryShadows = buildRandomDripShadow({
    count: 24,
    color: [245, 184, 0],
    minAlpha: 0.27,
    maxAlpha: 0.4,
    minY: -820,
    maxY: -340,
    minSpread: 2,
    maxSpread: 6,
    jitterX: 2.6
  })

  const primaryThickShadows = buildRandomDripShadow({
    count: 4,
    color: [245, 184, 0],
    minAlpha: 0.34,
    maxAlpha: 0.45,
    minY: -820,
    maxY: -340,
    minSpread: 0,
    maxSpread: 1,
    jitterX: 5.5
  })

  const secondaryShadows = buildRandomDripShadow({
    count: 20,
    color: [255, 211, 76],
    minAlpha: 0.19,
    maxAlpha: 0.26,
    minY: -860,
    maxY: -380,
    minSpread: 3,
    maxSpread: 6,
    jitterX: 3.2
  })

  rootStyle.setProperty(HONEY_DRIP_VAR_A, `${primaryShadows}, ${primaryThickShadows}`)
  rootStyle.setProperty(HONEY_DRIP_VAR_B, secondaryShadows)
  window.__bbHoneyDripsInitialized = true
}

const supportsFinePointerHover = () => {
  if (typeof window.matchMedia !== "function") {
    return false
  }

  return window.matchMedia("(hover: hover) and (pointer: fine)").matches
}

const resetHoneyParallax = (card) => {
  if (!card || !(card instanceof Element)) {
    return
  }

  card.style.setProperty(HONEY_PARALLAX_VAR_X, "0px")
  card.style.setProperty(HONEY_PARALLAX_VAR_Y, "0px")
}

const resetActiveHoneyParallax = () => {
  if (window.__bbHoneyParallaxActiveCard) {
    resetHoneyParallax(window.__bbHoneyParallaxActiveCard)
    window.__bbHoneyParallaxActiveCard = null
  }
}

const resetAllHoneyParallax = () => {
  resetActiveHoneyParallax()
  document.querySelectorAll(HONEY_PARALLAX_TARGET_SELECTOR).forEach((card) => resetHoneyParallax(card))
}

const updateHoneyParallaxFromPointer = (event) => {
  if (!document.documentElement.classList.contains(BUZZ_MODE_CLASS) || !supportsFinePointerHover()) {
    resetActiveHoneyParallax()
    return
  }

  const eventTarget = event.target
  const hoveredCard =
    eventTarget instanceof Element ? eventTarget.closest(HONEY_PARALLAX_TARGET_SELECTOR) : null

  if (window.__bbHoneyParallaxActiveCard && window.__bbHoneyParallaxActiveCard !== hoveredCard) {
    resetHoneyParallax(window.__bbHoneyParallaxActiveCard)
  }

  if (!hoveredCard) {
    window.__bbHoneyParallaxActiveCard = null
    return
  }

  const rect = hoveredCard.getBoundingClientRect()
  if (!rect.width || !rect.height) {
    resetHoneyParallax(hoveredCard)
    window.__bbHoneyParallaxActiveCard = hoveredCard
    return
  }

  const progressX = clamp((event.clientX - rect.left) / rect.width, 0, 1)
  const progressY = clamp((event.clientY - rect.top) / rect.height, 0, 1)
  const offsetX = roundTo((progressX - 0.5) * HONEY_PARALLAX_MAX_X * 2, 2)
  const offsetY = roundTo((progressY - 0.5) * HONEY_PARALLAX_MAX_Y * 2, 2)

  hoveredCard.style.setProperty(HONEY_PARALLAX_VAR_X, `${offsetX}px`)
  hoveredCard.style.setProperty(HONEY_PARALLAX_VAR_Y, `${offsetY}px`)
  window.__bbHoneyParallaxActiveCard = hoveredCard
}

const ensureHoneyParallaxTracking = () => {
  if (window.__bbHoneyParallaxTrackingInitialized) {
    return
  }

  window.__bbHoneyParallaxTrackingInitialized = true
  document.addEventListener("pointermove", updateHoneyParallaxFromPointer, {passive: true})
  document.addEventListener("pointerout", (event) => {
    if (!event.relatedTarget) {
      resetActiveHoneyParallax()
    }
  })
  window.addEventListener("blur", resetActiveHoneyParallax)
}

const randomBetweenInt = (min, max) => Math.floor(randomInRange(min, max + 1))

const clearHoneySheenTimeouts = () => {
  if (window.__bbHoneySheenNextTimeout) {
    window.clearTimeout(window.__bbHoneySheenNextTimeout)
    window.__bbHoneySheenNextTimeout = null
  }

  if (window.__bbHoneySheenWaveTimeout) {
    window.clearTimeout(window.__bbHoneySheenWaveTimeout)
    window.__bbHoneySheenWaveTimeout = null
  }
}

const clearActiveHoneySheenCard = () => {
  if (window.__bbHoneySheenActiveCard && window.__bbHoneySheenActiveCard.classList) {
    window.__bbHoneySheenActiveCard.classList.remove(HONEY_SHEEN_ACTIVE_CLASS)
  }
  window.__bbHoneySheenActiveCard = null
}

const getBuzzSoundCards = () =>
  Array.from(document.querySelectorAll(".bb-sound-grid .bb-sound-card"))

const scheduleNextHoneySheenWave = (runId) => {
  if (!document.documentElement.classList.contains(BUZZ_MODE_CLASS)) {
    return
  }

  const delay = randomBetweenInt(HONEY_SHEEN_MIN_DELAY_MS, HONEY_SHEEN_MAX_DELAY_MS)
  window.__bbHoneySheenNextTimeout = window.setTimeout(() => {
    if (window.__bbHoneySheenRunId !== runId) {
      return
    }
    triggerHoneySheenWave(runId)
  }, delay)
}

const triggerHoneySheenWave = (runId) => {
  if (window.__bbHoneySheenRunId !== runId) {
    return
  }

  if (!document.documentElement.classList.contains(BUZZ_MODE_CLASS)) {
    return
  }

  const cards = getBuzzSoundCards()
  if (!cards.length) {
    scheduleNextHoneySheenWave(runId)
    return
  }

  clearActiveHoneySheenCard()

  let candidates = cards
  if (window.__bbHoneySheenLastCard && cards.length > 1) {
    candidates = cards.filter((card) => card !== window.__bbHoneySheenLastCard)
  }

  const nextCard = candidates[Math.floor(Math.random() * candidates.length)] || cards[0]
  nextCard.classList.add(HONEY_SHEEN_ACTIVE_CLASS)
  window.__bbHoneySheenActiveCard = nextCard
  window.__bbHoneySheenLastCard = nextCard

  window.__bbHoneySheenWaveTimeout = window.setTimeout(() => {
    if (window.__bbHoneySheenRunId !== runId) {
      return
    }
    if (nextCard.classList) {
      nextCard.classList.remove(HONEY_SHEEN_ACTIVE_CLASS)
    }
    if (window.__bbHoneySheenActiveCard === nextCard) {
      window.__bbHoneySheenActiveCard = null
    }
    scheduleNextHoneySheenWave(runId)
  }, HONEY_SHEEN_WAVE_MS)
}

const startHoneySheenWaves = () => {
  window.__bbHoneySheenRunId = (window.__bbHoneySheenRunId || 0) + 1
  const runId = window.__bbHoneySheenRunId

  clearHoneySheenTimeouts()
  clearActiveHoneySheenCard()

  if (!document.documentElement.classList.contains(BUZZ_MODE_CLASS)) {
    return
  }

  scheduleNextHoneySheenWave(runId)
}

const stopHoneySheenWaves = () => {
  window.__bbHoneySheenRunId = (window.__bbHoneySheenRunId || 0) + 1
  clearHoneySheenTimeouts()
  clearActiveHoneySheenCard()
  window.__bbHoneySheenLastCard = null
}

const applyDesktopNavState = (collapsed) => {
  document.documentElement.classList.toggle(DESKTOP_NAV_COLLAPSED_CLASS, collapsed)
  if (document.body) {
    document.body.classList.toggle(DESKTOP_NAV_COLLAPSED_CLASS, collapsed)
  }

  const desktopOffset = collapsed ? "52px" : "180px"
  const isDesktop = window.matchMedia("(min-width: 1024px)").matches

  document.querySelectorAll(".desktop-nav-main").forEach((mainEl) => {
    mainEl.style.paddingLeft = isDesktop ? desktopOffset : ""
  })
}

const getAudioContextCtor = () => window.AudioContext || window.webkitAudioContext || null

const parsePercent = (
  value,
  fallback = MAX_VOLUME_PERCENT_DEFAULT,
  maxPercent = MAX_VOLUME_PERCENT_DEFAULT
) => {
  const parseNumeric = (input) => {
    if (typeof input === "number" && Number.isFinite(input)) {
      return input
    }
    if (typeof input === "string") {
      const parsed = parseFloat(input.trim())
      if (!Number.isNaN(parsed)) {
        return parsed
      }
    }
    return null
  }

  const parsedValue = parseNumeric(value)
  const parsedFallback = parseNumeric(fallback)
  const base = parsedValue === null ? (parsedFallback === null ? maxPercent : parsedFallback) : parsedValue
  return clamp(Math.round(base), 0, maxPercent)
}

const percentToGain = (percent, maxPercent = MAX_VOLUME_PERCENT_DEFAULT) => {
  const clampedPercent = clamp(Math.round(percent), 0, maxPercent)
  if (clampedPercent <= 100) {
    return roundTo(clampedPercent / 100)
  }
  const boosted = 1 + (clampedPercent - 100) * 0.01
  return roundTo(Math.min(boosted, BOOST_CAP))
}

const setElementGain = (audio, gain) => {
  if (!audio) {
    return
  }

  const clampedGain = clamp(gain, 0, BOOST_CAP)
  const elementVolume = Math.min(clampedGain, 1)

  try {
    audio.volume = elementVolume
  } catch (_err) {
    audio.volume = 1
  }

  if (audio.__gainNode) {
    audio.__gainNode.gain.value = clampedGain > 1 ? clampedGain : 1
  }
}

let activeLocalPlayer = null

const stopActiveLocalPlayer = () => {
  if (activeLocalPlayer && typeof activeLocalPlayer.stopPlayback === "function") {
    activeLocalPlayer.stopPlayback()
  }
}

const clipDurationCacheKey = (source) => `${CLIP_DURATION_CACHE_PREFIX}${source}`

const readCachedClipDuration = (source) => {
  if (!source) {
    return null
  }

  const memoryCached = clipDurationMemoryCache.get(source)
  if (Number.isFinite(memoryCached) && memoryCached > 0) {
    return memoryCached
  }

  try {
    const raw = window.localStorage.getItem(clipDurationCacheKey(source))
    if (!raw) {
      return null
    }

    const parsed = JSON.parse(raw)
    const duration = Number(parsed?.duration)
    const cachedAt = Number(parsed?.cachedAt)

    if (!Number.isFinite(duration) || duration <= 0) {
      return null
    }

    if (Number.isFinite(cachedAt) && Date.now() - cachedAt > CLIP_DURATION_CACHE_TTL_MS) {
      window.localStorage.removeItem(clipDurationCacheKey(source))
      return null
    }

    clipDurationMemoryCache.set(source, duration)
    return duration
  } catch (_err) {
    return null
  }
}

const writeCachedClipDuration = (source, duration) => {
  if (!source || !Number.isFinite(duration) || duration <= 0) {
    return
  }

  const normalized = roundTo(duration, 3)
  clipDurationMemoryCache.set(source, normalized)

  try {
    window.localStorage.setItem(
      clipDurationCacheKey(source),
      JSON.stringify({duration: normalized, cachedAt: Date.now()})
    )
  } catch (_err) {}
}

const clipDurationProbePromises = new Map()

const loadClipDuration = (source) => {
  if (!source) {
    return Promise.resolve(null)
  }

  const cached = readCachedClipDuration(source)
  if (Number.isFinite(cached) && cached > 0) {
    return Promise.resolve(cached)
  }

  const inFlight = clipDurationProbePromises.get(source)
  if (inFlight) {
    return inFlight
  }

  const probePromise = new Promise((resolve) => {
    const probe = new Audio()
    probe.preload = "metadata"

    const cleanup = () => {
      probe.removeEventListener("loadedmetadata", onLoadedMetadata)
      probe.removeEventListener("error", onError)
      probe.src = ""
    }

    const onLoadedMetadata = () => {
      const duration = probe.duration
      if (Number.isFinite(duration) && duration > 0) {
        writeCachedClipDuration(source, duration)
        cleanup()
        resolve(duration)
        return
      }

      cleanup()
      resolve(null)
    }

    const onError = () => {
      cleanup()
      resolve(null)
    }

    probe.addEventListener("loadedmetadata", onLoadedMetadata)
    probe.addEventListener("error", onError)
    probe.src = source
  })

  clipDurationProbePromises.set(source, probePromise)

  probePromise.finally(() => {
    clipDurationProbePromises.delete(source)
  })

  return probePromise
}

window.addEventListener("phx:stop-all-sounds", stopActiveLocalPlayer)

let Hooks = {}
Hooks.NowPlayingCard = {
  mounted() {
    this.progressFillEl = this.el.querySelector("[data-role='now-playing-progress-fill']")
    this.bylineEl = this.el.querySelector("[data-role='now-playing-byline']")
    this.signature = null
    this.eventId = 0
    this.source = ""
    this.startedAtMs = null
    this.durationSeconds = null
    this.durationRequestToken = 0
    this.animationFrame = null
    this.bylineTimer = null
    this.tick = this.tick.bind(this)
    this.syncFromDataset(true)
  },
  updated() {
    this.syncFromDataset()
  },
  destroyed() {
    this.stopTicking()
    this.clearBylineTimer()
    this.durationRequestToken += 1
  },
  parseEventId() {
    const parsed = Number(this.el.dataset.nowPlayingEventId)
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0
  },
  parseStartedAtMs() {
    const parsed = Number(this.el.dataset.nowPlayingStartedAtMs)
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null
  },
  syncFromDataset(force = false) {
    const eventId = this.parseEventId()
    const source = (this.el.dataset.nowPlayingSource || "").trim()
    const startedAtMs = this.parseStartedAtMs()
    const signature = `${eventId}|${source}|${startedAtMs ?? ""}`

    if (!force && signature === this.signature) {
      this.eventId = eventId
      this.startedAtMs = startedAtMs
      this.syncBylineVisibility()
      return
    }

    this.signature = signature
    this.eventId = eventId
    this.source = source
    this.startedAtMs = startedAtMs
    this.durationSeconds = null
    this.durationRequestToken += 1

    this.stopTicking()
    this.setProgress(0)

    if (eventId <= 0) {
      this.hideByline()
      return
    }

    this.syncBylineVisibility()
    this.resolveDuration(this.durationRequestToken)
    this.startTicking()
  },
  resolveDuration(requestToken) {
    if (!this.source) {
      return
    }

    loadClipDuration(this.source).then((duration) => {
      if (requestToken !== this.durationRequestToken) {
        return
      }

      if (Number.isFinite(duration) && duration > 0) {
        this.durationSeconds = duration
      }
    })
  },
  startTicking() {
    this.stopTicking()
    this.animationFrame = window.requestAnimationFrame(this.tick)
  },
  stopTicking() {
    if (this.animationFrame) {
      window.cancelAnimationFrame(this.animationFrame)
      this.animationFrame = null
    }
  },
  tick() {
    if (this.eventId <= 0) {
      this.setProgress(0)
      return
    }

    const startedAtMs = this.startedAtMs || Date.now()
    const elapsedSeconds = Math.max(0, (Date.now() - startedAtMs) / 1000)

    if (Number.isFinite(this.durationSeconds) && this.durationSeconds > 0) {
      const ratio = clamp(elapsedSeconds / this.durationSeconds, 0, 1)
      this.setProgress(ratio * 100)

      if (ratio < 1) {
        this.animationFrame = window.requestAnimationFrame(this.tick)
      }
      return
    }

    const fallbackDurationSeconds = 15
    const fallbackRatio = clamp(elapsedSeconds / fallbackDurationSeconds, 0, 1)
    this.setProgress(fallbackRatio * 100)

    if (fallbackRatio < 1) {
      this.animationFrame = window.requestAnimationFrame(this.tick)
    }
  },
  setProgress(percent) {
    if (!this.progressFillEl) {
      return
    }

    const bounded = clamp(percent, 0, 100)
    this.progressFillEl.style.width = `${bounded}%`
  },
  clearBylineTimer() {
    if (this.bylineTimer) {
      window.clearTimeout(this.bylineTimer)
      this.bylineTimer = null
    }
  },
  syncBylineVisibility() {
    if (!this.bylineEl) {
      return
    }

    this.clearBylineTimer()

    if ((this.bylineEl.textContent || "").trim() === "") {
      this.bylineEl.classList.add("bb-now-playing-byline-hidden")
      return
    }

    if (this.eventId <= 0 || !Number.isFinite(this.startedAtMs)) {
      this.bylineEl.classList.add("bb-now-playing-byline-hidden")
      return
    }

    const elapsedMs = Date.now() - this.startedAtMs
    const remainingMs = 1000 - elapsedMs

    if (remainingMs <= 0) {
      this.bylineEl.classList.add("bb-now-playing-byline-hidden")
      return
    }

    this.bylineEl.classList.remove("bb-now-playing-byline-hidden")
    this.bylineTimer = window.setTimeout(() => {
      this.bylineEl.classList.add("bb-now-playing-byline-hidden")
    }, remainingMs)
  },
  hideByline() {
    if (!this.bylineEl) {
      return
    }

    this.clearBylineTimer()
    this.bylineEl.classList.add("bb-now-playing-byline-hidden")
  }
}

Hooks.LocalPlayer = {
  mounted() {
    this.audio = null
    this.audioContext = null
    this.cleanup = null
    this.boundAudio = null
    this.previewTimer = null
    this.previewStartedAt = null
    this.remountGuardTimer = null
    this.cardEl = null
    this.previewTimeEl = null
    this.previewWaveEl = null
    this.durationEl = null
    this.durationSource = null
    this.durationLoadToken = 0
    this.previewBars = []
    this.waveHeights = [6, 10, 14, 18, 14, 18, 10, 14, 18, 14, 10, 6, 14, 10, 18, 14, 6, 14, 10, 18]
    this.waveBarWidth = 3
    this.waveGap = 2
    this.handleClick = this.handleClick.bind(this)
    this.handleRemotePlay = this.handleRemotePlay.bind(this)
    this.handleAudioEnded = this.handleAudioEnded.bind(this)
    this.handleWindowResize = this.handleWindowResize.bind(this)
    this.syncPreviewElements()
    this.el.addEventListener("click", this.handleClick)
    window.addEventListener("phx:play-local-sound", this.handleRemotePlay)
    this.rebuildPreviewBars()
    this.loadClipDuration()
    this.adoptActivePlaybackIfNeeded()
    window.addEventListener("resize", this.handleWindowResize)
  },
  updated() {
    this.syncPreviewElements()
    this.rebuildPreviewBars()
    this.loadClipDuration()
    if (this.audio && !this.audio.paused) {
      this.configureGain(this.readGain())
    }
  },
  destroyed() {
    const keepAliveForPotentialRemount =
      activeLocalPlayer === this && this.audio && !this.audio.paused

    this.durationLoadToken += 1
    this.el.removeEventListener("click", this.handleClick)
    window.removeEventListener("phx:play-local-sound", this.handleRemotePlay)
    window.removeEventListener("resize", this.handleWindowResize)

    if (keepAliveForPotentialRemount) {
      this.clearPreviewTimer()

      this.remountGuardTimer = window.setTimeout(() => {
        if (activeLocalPlayer === this) {
          this.stopPlayback()
        }
      }, 350)

      return
    }

    this.stopPlayback()
  },
  clearRemountGuardTimer() {
    if (this.remountGuardTimer) {
      window.clearTimeout(this.remountGuardTimer)
      this.remountGuardTimer = null
    }
  },
  clearPreviewTimer() {
    if (this.previewTimer) {
      clearInterval(this.previewTimer)
      this.previewTimer = null
    }
  },
  handleAudioEnded() {
    this.stopPlayback()
  },
  bindAudioEvents(audio) {
    if (!audio) {
      return
    }

    this.unbindAudioEvents()
    audio.addEventListener("ended", this.handleAudioEnded)
    audio.addEventListener("error", this.handleAudioEnded)
    this.boundAudio = audio
  },
  unbindAudioEvents() {
    if (!this.boundAudio) {
      return
    }

    this.boundAudio.removeEventListener("ended", this.handleAudioEnded)
    this.boundAudio.removeEventListener("error", this.handleAudioEnded)
    this.boundAudio = null
  },
  adoptActivePlaybackIfNeeded() {
    const previousPlayer = activeLocalPlayer

    if (!previousPlayer || previousPlayer === this) {
      return
    }

    if (!previousPlayer.audio || previousPlayer.audio.paused) {
      return
    }

    if ((previousPlayer.el?.id || "") !== (this.el?.id || "")) {
      return
    }

    previousPlayer.clearRemountGuardTimer?.()
    previousPlayer.unbindAudioEvents?.()
    previousPlayer.clearPreviewTimer?.()

    this.audio = previousPlayer.audio
    this.audioContext = previousPlayer.audioContext
    this.cleanup = previousPlayer.cleanup
    this.previewStartedAt = previousPlayer.previewStartedAt || Date.now()

    previousPlayer.audio = null
    previousPlayer.audioContext = null
    previousPlayer.cleanup = null
    previousPlayer.previewStartedAt = null

    this.bindAudioEvents(this.audio)
    activeLocalPlayer = this
    this.setPlaying(true, this.previewStartedAt)
    this.configureGain(this.readGain())
  },
  async handleRemotePlay(event) {
    const requestedFilename =
      typeof event?.detail?.filename === "string" ? event.detail.filename.trim() : ""
    const currentFilename = (this.el.dataset.filename || "").trim()

    if (!requestedFilename || requestedFilename !== currentFilename) {
      return
    }

    if (activeLocalPlayer && activeLocalPlayer !== this) {
      activeLocalPlayer.stopPlayback()
    }

    await this.startPlayback()
  },
  handleWindowResize() {
    this.rebuildPreviewBars()
  },
  syncPreviewElements() {
    this.cardEl = this.el.closest(".bb-sound-card")
    this.previewTimeEl = this.cardEl?.querySelector("[data-role='preview-time']") || null
    this.previewWaveEl = this.cardEl?.querySelector(".bb-preview-wave") || null
    this.durationEl = this.cardEl?.querySelector("[data-role='clip-duration']") || null
  },
  rebuildPreviewBars() {
    if (!this.previewWaveEl) {
      return
    }

    const width = this.previewWaveEl.clientWidth
    const perBar = this.waveBarWidth + this.waveGap
    const count =
      width > 0
        ? Math.max(12, Math.floor((width + this.waveGap) / perBar))
        : 24
    const isPreviewing = this.cardEl?.classList.contains("previewing")
    const fragment = document.createDocumentFragment()

    for (let idx = 0; idx < count; idx += 1) {
      const bar = document.createElement("span")
      const height = this.waveHeights[idx % this.waveHeights.length]
      bar.className = isPreviewing ? "bar active" : "bar"
      bar.style.setProperty("--h", `${height}px`)
      bar.style.setProperty("--d", `${(idx * 0.07).toFixed(2)}s`)
      fragment.appendChild(bar)
    }

    this.previewWaveEl.innerHTML = ""
    this.previewWaveEl.appendChild(fragment)
    this.previewBars = Array.from(this.previewWaveEl.querySelectorAll(".bar"))
  },
  readGain() {
    const raw = parseFloat(this.el.dataset.volume)
    return Number.isFinite(raw) ? clamp(raw, 0, BOOST_CAP) : 1
  },
  resolveSource() {
    const sourceType = this.el.dataset.sourceType
    const url = this.el.dataset.url
    const filename = this.el.dataset.filename

    if (sourceType === "url" && url) {
      return url
    }
    if (filename) {
      return buildUploadUrl(filename)
    }
    return null
  },
  loadClipDuration() {
    if (!this.durationEl) {
      return
    }

    const source = this.resolveSource()
    if (!source) {
      this.durationSource = null
      this.durationEl.textContent = "--:--"
      return
    }

    // Always hydrate duration text from cache first so LiveView re-renders
    // don't leave a recreated element stuck at the placeholder.
    const cachedDuration = readCachedClipDuration(source)
    if (Number.isFinite(cachedDuration) && cachedDuration > 0) {
      this.durationSource = source
      this.durationEl.textContent = this.formatClipDuration(cachedDuration)
      return
    }

    if (this.durationSource === source) {
      return
    }

    this.durationSource = source
    this.durationEl.textContent = "--:--"
    this.durationLoadToken += 1
    const token = this.durationLoadToken
    const probe = new Audio()
    probe.preload = "metadata"

    const cleanup = () => {
      probe.removeEventListener("loadedmetadata", onLoadedMetadata)
      probe.removeEventListener("error", onError)
      probe.src = ""
    }

    const onLoadedMetadata = () => {
      if (token !== this.durationLoadToken) {
        cleanup()
        return
      }

      const duration = probe.duration
      if (Number.isFinite(duration) && duration > 0) {
        writeCachedClipDuration(source, duration)
        this.durationEl.textContent = this.formatClipDuration(duration)
      } else {
        this.durationEl.textContent = "--:--"
      }
      cleanup()
    }

    const onError = () => {
      if (token === this.durationLoadToken && this.durationEl) {
        this.durationEl.textContent = "--:--"
      }
      cleanup()
    }

    probe.addEventListener("loadedmetadata", onLoadedMetadata)
    probe.addEventListener("error", onError)
    probe.src = source
  },
  async handleClick(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.audio && !this.audio.paused) {
      this.stopPlayback()
      return
    }

    if (activeLocalPlayer && activeLocalPlayer !== this) {
      activeLocalPlayer.stopPlayback()
    }

    await this.startPlayback()
  },
  async startPlayback() {
    this.stopPlayback()
    const source = this.resolveSource()

    const audio = new Audio()

    if (!source) {
      return
    }
    audio.src = source

    this.bindAudioEvents(audio)
    this.audio = audio

    await this.configureGain(this.readGain())

    try {
      await audio.play()
      this.setPlaying(true)
      activeLocalPlayer = this
    } catch (error) {
      console.error("Audio playback failed", error)
      this.stopPlayback()
    }
  },
  async configureGain(targetGain) {
    if (!this.audio) {
      return
    }

    this.releaseBoost()

    const normalized = clamp(targetGain, 0, BOOST_CAP)
    const ContextCtor = getAudioContextCtor()

    if (!ContextCtor || normalized <= 1) {
      setElementGain(this.audio, normalized)
      return
    }

    if (!this.audioContext) {
      this.audioContext = new ContextCtor()
    }

    if (this.audioContext.state === "suspended") {
      try {
        await this.audioContext.resume()
      } catch (_err) {}
    }

    try {
      const source = this.audioContext.createMediaElementSource(this.audio)
      const gainNode = this.audioContext.createGain()
      gainNode.gain.value = normalized
      source.connect(gainNode).connect(this.audioContext.destination)
      this.audio.__gainNode = gainNode
      setElementGain(this.audio, normalized)

      this.cleanup = () => {
        try {
          source.disconnect()
        } catch (_err) {}
        try {
          gainNode.disconnect()
        } catch (_err) {}
        if (this.audio && this.audio.__gainNode === gainNode) {
          delete this.audio.__gainNode
        }
      }
    } catch (error) {
      console.warn("Unable to apply playback boost", error)
      setElementGain(this.audio, Math.min(normalized, 1))
    }
  },
  releaseBoost() {
    if (typeof this.cleanup === "function") {
      try {
        this.cleanup()
      } catch (_err) {}
    }
    this.cleanup = null
    if (this.audio) {
      delete this.audio.__gainNode
    }
  },
  stopPlayback() {
    this.clearRemountGuardTimer()
    this.unbindAudioEvents()
    this.releaseBoost()
    if (this.audio) {
      try {
        this.audio.pause()
        this.audio.currentTime = 0
      } catch (_err) {}
      this.audio = null
    }
    this.setPlaying(false)
    if (activeLocalPlayer === this) {
      activeLocalPlayer = null
    }
  },
  formatPreviewTime(totalSeconds) {
    const safeSeconds = Math.max(0, Math.floor(totalSeconds))
    const minutes = Math.floor(safeSeconds / 60)
    const seconds = safeSeconds % 60
    return `${minutes}:${String(seconds).padStart(2, "0")}`
  },
  formatClipDuration(totalSeconds) {
    const safeSeconds = Math.max(0, Math.floor(totalSeconds))
    const hours = Math.floor(safeSeconds / 3600)
    const minutes = Math.floor((safeSeconds % 3600) / 60)
    const seconds = safeSeconds % 60

    if (hours > 0) {
      return `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
    }

    return `${minutes}:${String(seconds).padStart(2, "0")}`
  },
  startPreviewUi(startedAtMs = Date.now()) {
    this.previewStartedAt = Number.isFinite(startedAtMs) ? startedAtMs : Date.now()
    if (this.cardEl) {
      this.cardEl.classList.add("previewing")
    }
    this.rebuildPreviewBars()
    this.previewBars.forEach((bar) => bar.classList.add("active"))
    if (this.previewTimeEl) {
      const elapsed = Math.max(0, (Date.now() - this.previewStartedAt) / 1000)
      this.previewTimeEl.textContent = this.formatPreviewTime(elapsed)
    }
    this.clearPreviewTimer()
    this.previewTimer = setInterval(() => {
      if (!this.previewStartedAt || !this.previewTimeEl) {
        return
      }
      const elapsed = (Date.now() - this.previewStartedAt) / 1000
      this.previewTimeEl.textContent = this.formatPreviewTime(elapsed)
    }, 250)
  },
  stopPreviewUi() {
    this.clearPreviewTimer()
    this.previewStartedAt = null
    if (this.cardEl) {
      this.cardEl.classList.remove("previewing")
    }
    this.previewBars.forEach((bar) => bar.classList.remove("active"))
    if (this.previewTimeEl) {
      this.previewTimeEl.textContent = "0:00"
    }
  },
  setPlaying(isPlaying, startedAtMs = Date.now()) {
    const playIcon = this.el.querySelector(".play-icon")
    const stopIcon = this.el.querySelector(".stop-icon")

    if (!playIcon || !stopIcon) {
      return
    }

    if (isPlaying) {
      playIcon.classList.add("hidden")
      stopIcon.classList.remove("hidden")
      this.startPreviewUi(startedAtMs)
    } else {
      playIcon.classList.remove("hidden")
      stopIcon.classList.add("hidden")
      this.stopPreviewUi()
    }
  }
}

Hooks.CooldownTimer = {
  mounted() {
    this.valueEl = this.el.querySelector("[data-role='cooldown-value']") || this.el
    this.endMs = null
    this.baseRemainingMs = null
    this.startedAt = null
    this.lastSignature = null
    this.frame = null
    this.tick = this.tick.bind(this)
    this.syncFromDataset(true)
  },
  updated() {
    this.syncFromDataset()
  },
  destroyed() {
    this.stopTicking()
  },
  parseEndMs() {
    const raw = this.el.dataset.cooldownEndMs
    const parsed = Number(raw)
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null
  },
  parseRemainingMs() {
    const raw = this.el.dataset.cooldownRemainingMs
    const parsed = Number(raw)
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : null
  },
  syncFromDataset(force = false) {
    const endMs = this.parseEndMs()
    const remainingMs = this.parseRemainingMs()
    const signature = `${endMs ?? ""}|${remainingMs ?? ""}`

    if (!force && signature === this.lastSignature) {
      return
    }

    this.lastSignature = signature
    this.stopTicking()
    this.endMs = endMs
    this.baseRemainingMs = remainingMs
    this.startedAt = remainingMs !== null ? performance.now() : null
    this.tick()
  },
  stopTicking() {
    if (this.frame) {
      cancelAnimationFrame(this.frame)
      this.frame = null
    }
  },
  setState(state) {
    this.el.dataset.state = state
  },
  tick() {
    if (!this.valueEl) {
      return
    }

    if (!this.endMs) {
      if (this.baseRemainingMs === null || this.startedAt === null) {
        this.valueEl.textContent = "Ready"
        this.setState("ready")
        return
      }
    }

    const remaining =
      this.baseRemainingMs !== null && this.startedAt !== null
        ? this.baseRemainingMs - (performance.now() - this.startedAt)
        : this.endMs - Date.now()

    if (remaining <= 0) {
      this.valueEl.textContent = "Ready"
      this.setState("ready")
      return
    }

    this.valueEl.textContent = formatCooldownDuration(remaining)
    this.setState("cooling")
    this.frame = requestAnimationFrame(this.tick)
  }
}

Hooks.VolumeControl = {
  mounted() {
    this.previewAudio = null
    this.previewContext = null
    this.previewSource = null
    this.previewGain = null
    this.objectUrl = null
    this.lastFile = null
    this.pushTimer = null
    this.previewLabel = "Preview"

    this.handleSliderInput = this.handleSliderInput.bind(this)
    this.handlePreviewClick = this.handlePreviewClick.bind(this)

    this.syncDataset()
    this.bindElements()

    this.setPercent(this.initialPercent(), {emit: false})
  },
  updated() {
    const previousKind = this.previewKind
    const previousSrc = this.previewSrc

    this.syncDataset()
    this.bindElements()
    this.setPercent(this.initialPercent(), {emit: false})

    if (previousKind && previousKind !== this.previewKind) {
      this.stopPreview(true)
    } else if (previousSrc !== this.previewSrc && this.previewKind !== "local-upload") {
      this.stopPreview()
    }
  },
  destroyed() {
    if (this.slider) {
      this.slider.removeEventListener("input", this.handleSliderInput)
    }
    if (this.previewButton) {
      this.previewButton.removeEventListener("click", this.handlePreviewClick)
    }
    if (this.pushTimer) {
      clearTimeout(this.pushTimer)
      this.pushTimer = null
    }
    this.stopPreview(true)
    if (this.previewSource) {
      try {
        this.previewSource.disconnect()
      } catch (_err) {}
    }
    if (this.previewGain) {
      try {
        this.previewGain.disconnect()
      } catch (_err) {}
    }
    this.previewSource = null
    this.previewGain = null
    if (this.previewContext) {
      try {
        this.previewContext.close()
      } catch (_err) {}
      this.previewContext = null
    }
  },
  syncDataset() {
    const dataset = this.el.dataset
    const parsedMax = parseInt(dataset.maxPercent || "", 10)
    this.maxPercent =
      Number.isInteger(parsedMax) && parsedMax > 0 ? parsedMax : MAX_VOLUME_PERCENT_DEFAULT
    this.pushEventName = dataset.pushEvent || null
    this.volumeTarget = dataset.volumeTarget || null
    this.previewKind = dataset.previewKind || "existing"
    this.fileInputId = dataset.fileInputId || null
    this.urlInputId = dataset.urlInputId || null
    this.previewSrc = dataset.previewSrc || ""
  },
  bindElements() {
    const slider = this.el.querySelector("[data-role='volume-slider']")
    if (this.slider !== slider) {
      if (this.slider) {
        this.slider.removeEventListener("input", this.handleSliderInput)
      }
      this.slider = slider
      if (this.slider) {
        this.slider.addEventListener("input", this.handleSliderInput)
      }
    }

    const previewButton = this.el.querySelector("[data-role='volume-preview']")
    if (this.previewButton !== previewButton) {
      if (this.previewButton) {
        this.previewButton.removeEventListener("click", this.handlePreviewClick)
      }
      this.previewButton = previewButton
      if (this.previewButton) {
        this.previewButton.addEventListener("click", this.handlePreviewClick)
      }
    }

    if (this.previewButton) {
      this.previewLabel = this.previewButton.textContent?.trim() || this.previewLabel
    }

    this.hiddenInput = this.el.querySelector("[data-role='volume-hidden']")
    this.display = this.el.querySelector("[data-role='volume-display']")
  },
  initialPercent() {
    const hiddenValue = this.hiddenInput?.value
    const sliderValue = this.slider?.value
    return parsePercent(hiddenValue ?? sliderValue ?? this.maxPercent, this.maxPercent, this.maxPercent)
  },
  setPercent(percent, {emit = false} = {}) {
    const bounded = clamp(Math.round(percent), 0, this.maxPercent)
    if (this.slider && Number(this.slider.value) !== bounded) {
      this.slider.value = bounded
    }

    if (this.hiddenInput && Number(this.hiddenInput.value) !== bounded) {
      this.hiddenInput.value = bounded
    }

    if (this.display) {
      this.display.textContent = `${bounded}%`
    }

    if (emit) {
      this.queuePush(bounded)
    }

    this.updatePreviewGain(bounded)
  },
  async handleSliderInput(event) {
    const fallback = this.hiddenInput?.value ?? this.slider?.value ?? this.maxPercent
    const nextPercent = parsePercent(event.target.value, fallback, this.maxPercent)
    event.target.value = nextPercent
    this.setPercent(nextPercent, {emit: true})
  },
  queuePush(percent) {
    if (!this.pushEventName) {
      return
    }

    if (this.pushTimer) {
      clearTimeout(this.pushTimer)
    }

    this.pushTimer = setTimeout(() => {
      const payload = {volume: percent}
      if (this.volumeTarget) {
        payload.target = this.volumeTarget
      }
      this.pushEvent(this.pushEventName, payload)
      this.pushTimer = null
    }, 100)
  },
  async handlePreviewClick(event) {
    event.preventDefault()

    if (this.previewButton && this.previewButton.disabled) {
      return
    }

    if (this.previewAudio && !this.previewAudio.paused) {
      this.stopPreview()
      return
    }

    const src = this.getPreviewSource()
    if (!src) {
      return
    }

    if (!this.previewAudio) {
      this.previewAudio = new Audio()
      this.previewAudio.addEventListener("ended", () => this.stopPreview())
      this.previewAudio.addEventListener("error", () => this.stopPreview())
    }

    this.previewAudio.src = src

    const percent = parsePercent(
      this.hiddenInput?.value ?? this.slider?.value ?? this.maxPercent,
      this.maxPercent,
      this.maxPercent
    )
    const gain = percentToGain(percent, this.maxPercent)
    await this.ensurePreviewGraph(gain)
    this.applyPreviewGain(gain)

    try {
      await this.previewAudio.play()
      this.setPreviewState(true)
    } catch (error) {
      console.error("Preview playback failed", error)
      this.setPreviewState(false)
    }
  },
  async updatePreviewGain(percent) {
    const gain = percentToGain(percent, this.maxPercent)

    if (!this.previewAudio) {
      return
    }

    await this.ensurePreviewGraph(gain)
    this.applyPreviewGain(gain)
  },
  async ensurePreviewGraph(targetGain) {
    if (!this.previewAudio) {
      return
    }

    const needsBoost = targetGain > 1
    const ContextCtor = getAudioContextCtor()

    if (!needsBoost || !ContextCtor) {
      if (this.previewGain) {
        this.previewGain.gain.value = 1
      }
      return
    }

    if (!this.previewContext) {
      this.previewContext = new ContextCtor()
    }

    if (this.previewContext.state === "suspended") {
      try {
        await this.previewContext.resume()
      } catch (_err) {}
    }

    if (!this.previewSource) {
      try {
        this.previewSource = this.previewContext.createMediaElementSource(this.previewAudio)
      } catch (error) {
        console.warn("Preview gain setup failed", error)
        this.previewSource = null
        this.previewGain = null
        return
      }
    }

    if (!this.previewGain) {
      this.previewGain = this.previewContext.createGain()
      this.previewSource.connect(this.previewGain).connect(this.previewContext.destination)
    }
  },
  applyPreviewGain(targetGain) {
    if (!this.previewAudio) {
      return
    }

    const base = clamp(targetGain, 0, BOOST_CAP)
    const volume = Math.min(base, 1)

    try {
      this.previewAudio.volume = volume
    } catch (_err) {
      this.previewAudio.volume = 1
    }

    if (this.previewGain) {
      this.previewGain.gain.value = base > 1 ? base : 1
    }
  },
  getPreviewSource() {
    if (this.previewKind === "local-upload" && this.fileInputId) {
      const input = document.getElementById(this.fileInputId)
      const file = input && input.files && input.files[0]

      if (!file) {
        return null
      }

      if (this.lastFile !== file) {
        if (this.objectUrl) {
          URL.revokeObjectURL(this.objectUrl)
        }
        this.objectUrl = URL.createObjectURL(file)
        this.lastFile = file
      }

      return this.objectUrl
    }

    if (this.previewKind === "url") {
      if (this.urlInputId) {
        const urlInput = document.getElementById(this.urlInputId)
        const value =
          urlInput && typeof urlInput.value === "string" ? urlInput.value.trim() : ""
        if (value) {
          return value
        }
      }

      return this.previewSrc || null
    }

    return this.previewSrc || null
  },
  stopPreview(forceRevoke = false) {
    if (this.previewAudio) {
      try {
        this.previewAudio.pause()
        this.previewAudio.currentTime = 0
      } catch (_err) {}
      this.previewAudio.src = ""
    }
    this.setPreviewState(false)

    if (forceRevoke && this.objectUrl) {
      URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
      this.lastFile = null
    }
  },
  setPreviewState(isPlaying) {
    if (!this.previewButton) {
      return
    }

    this.previewButton.textContent = isPlaying ? "Stop Preview" : this.previewLabel
    this.previewButton.dataset.previewState = isPlaying ? "playing" : "stopped"
  }
}

Hooks.CopyButton = {
  mounted() {
    this.handleClick = async (e) => {
      e.preventDefault()
      const original = this.el.textContent
      const text =
        this.el.dataset.copyText ||
        this.el.getAttribute("data-copy-text") ||
        (this.el.nextElementSibling ? this.el.nextElementSibling.innerText : "")
      try {
        if (navigator.clipboard && window.isSecureContext) {
          await navigator.clipboard.writeText(text)
        } else {
          // Fallback for insecure contexts
          const ta = document.createElement("textarea")
          ta.value = text
          ta.style.position = "fixed"
          ta.style.opacity = "0"
          document.body.appendChild(ta)
          ta.select()
          document.execCommand("copy")
          document.body.removeChild(ta)
        }
        this.el.textContent = "Copied!"
        this.el.classList.add("text-green-600")
        setTimeout(() => {
          this.el.textContent = original
          this.el.classList.remove("text-green-600")
        }, 1500)
      } catch (_err) {
        this.el.textContent = "Copy failed"
        this.el.classList.add("text-red-600")
        setTimeout(() => {
          this.el.textContent = original
          this.el.classList.remove("text-red-600")
        }, 1500)
      }
    }
    this.el.addEventListener("click", this.handleClick)
  },
  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
  }
}

Hooks.QueenPick = {
  mounted() {
    this.rotationMs = this.readRotationMs()
    this.countdownEl = this.el.querySelector("[data-role='queen-pick-countdown']")
    this.titleEl = this.el.querySelector("[data-role='queen-pick-title']")
    this.metaEl = this.el.querySelector("[data-role='queen-pick-meta']")
    this.playButtonEl = this.el.querySelector("[data-role='queen-pick-play']")
    this.pickTimer = null
    this.countdownTimer = null
    this.nextPickDeadlineMs = null
    this.currentCandidateKey = null
    this.highlightedCard = null
    this.candidates = []

    this.handleVisibilityChange = () => {
      if (document.hidden) {
        this.clearTimers()
        this.stopCountdown()
        return
      }

      this.syncCandidates()
      this.syncWithBuzzMode()
    }

    document.addEventListener("visibilitychange", this.handleVisibilityChange)

    this.buzzClassObserver = new MutationObserver(() => {
      this.syncWithBuzzMode()
    })

    this.buzzClassObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class"]
    })

    this.syncCandidates()
    this.syncWithBuzzMode()
  },
  updated() {
    this.syncCandidates()

    if (!this.candidates.some((candidate) => candidate.key === this.currentCandidateKey)) {
      this.currentCandidateKey = null
    }

    this.syncWithBuzzMode()
  },
  destroyed() {
    this.clearTimers()
    this.stopCountdown()
    this.clearHighlightedCard()

    if (this.buzzClassObserver) {
      this.buzzClassObserver.disconnect()
      this.buzzClassObserver = null
    }

    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
  },
  readRotationMs() {
    const raw = parseInt(this.el.dataset.rotationMs || `${QUEEN_PICK_DEFAULT_ROTATION_MS}`, 10)
    if (!Number.isFinite(raw)) {
      return QUEEN_PICK_DEFAULT_ROTATION_MS
    }

    return Math.max(QUEEN_PICK_MIN_ROTATION_MS, raw)
  },
  isBuzzModeActive() {
    return document.documentElement.classList.contains(BUZZ_MODE_CLASS)
  },
  syncCandidates() {
    const cards = Array.from(document.querySelectorAll(".bb-sound-grid .bb-sound-card"))
    this.candidates = cards
      .map((cardEl) => this.extractCandidate(cardEl))
      .filter((candidate) => candidate !== null)
  },
  extractCandidate(cardEl) {
    if (!(cardEl instanceof Element)) {
      return null
    }

    const playButton = cardEl.querySelector("button[phx-click='play'][phx-value-name]")
    const filename =
      (playButton?.getAttribute("phx-value-name") || cardEl.dataset.queenFilename || "").trim()

    if (!filename) {
      return null
    }

    const title = (cardEl.dataset.queenTitle || cardEl.querySelector(".bb-card-title")?.textContent || filename).trim()
    const uploader = (cardEl.dataset.queenUploader || cardEl.querySelector(".bb-card-uploader-name")?.textContent || "").trim()
    const tags = Array.from(cardEl.querySelectorAll(".bb-card-tag-label"))
      .map((tagEl) => tagEl.textContent.trim())
      .filter(Boolean)
      .slice(0, 2)

    return {
      key: cardEl.id || filename,
      filename,
      title,
      uploader,
      tags,
      cardEl
    }
  },
  formatCountdown(remainingMs) {
    const seconds = Math.max(0, Math.ceil(remainingMs / 1000))
    const minutesPart = Math.floor(seconds / 60)
    const secondsPart = seconds % 60
    return `${padNumber(minutesPart)}:${padNumber(secondsPart)}`
  },
  updateCountdown() {
    if (!this.countdownEl || !Number.isFinite(this.nextPickDeadlineMs)) {
      return
    }

    const remaining = Math.max(0, this.nextPickDeadlineMs - Date.now())
    this.countdownEl.textContent = this.formatCountdown(remaining)
  },
  beginCountdown(delayMs) {
    this.stopCountdown()
    this.nextPickDeadlineMs = Date.now() + delayMs
    this.updateCountdown()
    this.countdownTimer = window.setInterval(() => this.updateCountdown(), 500)
  },
  stopCountdown() {
    if (this.countdownTimer) {
      window.clearInterval(this.countdownTimer)
      this.countdownTimer = null
    }
  },
  clearTimers() {
    if (this.pickTimer) {
      window.clearTimeout(this.pickTimer)
      this.pickTimer = null
    }
  },
  clearHighlightedCard() {
    if (this.highlightedCard && this.highlightedCard.classList) {
      this.highlightedCard.classList.remove("bb-queen-card-active")
    }
    this.highlightedCard = null
  },
  setHighlightedCard(cardEl) {
    if (this.highlightedCard && this.highlightedCard !== cardEl && this.highlightedCard.classList) {
      this.highlightedCard.classList.remove("bb-queen-card-active")
    }

    this.highlightedCard = cardEl
    if (cardEl && cardEl.classList) {
      cardEl.classList.add("bb-queen-card-active")
    }
  },
  renderCandidate(candidate) {
    if (!candidate) {
      this.renderEmptyState()
      return
    }

    if (this.titleEl) {
      this.titleEl.textContent = candidate.title || candidate.filename
    }

    if (this.metaEl) {
      const metaParts = []
      if (candidate.uploader) {
        metaParts.push(`uploaded by ${candidate.uploader}`)
      }
      if (candidate.tags.length > 0) {
        metaParts.push(candidate.tags.join(" | "))
      }
      this.metaEl.textContent = metaParts.join("  ") || "Randomly selected from current results."
    }

    if (this.playButtonEl) {
      this.playButtonEl.removeAttribute("disabled")
      this.playButtonEl.setAttribute("phx-value-name", candidate.filename)
    }

    this.setHighlightedCard(candidate.cardEl)
  },
  renderEmptyState() {
    if (this.titleEl) {
      this.titleEl.textContent = "No sounds match current filters."
    }
    if (this.metaEl) {
      this.metaEl.textContent = "Adjust search or tags to repopulate Queen's Pick."
    }
    if (this.playButtonEl) {
      this.playButtonEl.setAttribute("disabled", "disabled")
      this.playButtonEl.setAttribute("phx-value-name", "")
    }
    if (this.countdownEl) {
      this.countdownEl.textContent = "--:--"
    }
    this.clearHighlightedCard()
  },
  pickRandomCandidate() {
    if (!this.candidates || this.candidates.length === 0) {
      return null
    }

    let pool = this.candidates
    if (this.currentCandidateKey && this.candidates.length > 1) {
      pool = this.candidates.filter((candidate) => candidate.key !== this.currentCandidateKey)
    }

    return pool[Math.floor(Math.random() * pool.length)] || this.candidates[0]
  },
  scheduleNextPick(delayMs = this.rotationMs) {
    if (!this.isBuzzModeActive()) {
      return
    }

    if (this.pickTimer) {
      window.clearTimeout(this.pickTimer)
      this.pickTimer = null
    }

    const safeDelay = Math.max(1000, delayMs)
    this.beginCountdown(safeDelay)

    this.pickTimer = window.setTimeout(() => {
      this.pickTimer = null
      this.runPick()
    }, safeDelay)
  },
  runPick() {
    if (!this.isBuzzModeActive() || document.hidden) {
      return
    }

    this.syncCandidates()
    const candidate = this.pickRandomCandidate()
    if (!candidate) {
      this.renderEmptyState()
      this.clearTimers()
      this.stopCountdown()
      return
    }

    this.currentCandidateKey = candidate.key
    this.renderCandidate(candidate)
    this.scheduleNextPick(this.rotationMs)
  },
  syncWithBuzzMode() {
    if (!this.isBuzzModeActive()) {
      this.clearTimers()
      this.stopCountdown()
      this.clearHighlightedCard()
      return
    }

    if (document.hidden) {
      return
    }

    if (!this.candidates || this.candidates.length === 0) {
      this.renderEmptyState()
      this.clearTimers()
      this.stopCountdown()
      return
    }

    const currentCandidate =
      this.candidates.find((candidate) => candidate.key === this.currentCandidateKey) || null

    if (!currentCandidate) {
      this.runPick()
      return
    }

    this.renderCandidate(currentCandidate)

    if (!this.pickTimer) {
      this.scheduleNextPick(this.rotationMs)
    }
  }
}

Hooks.BuzzModeToggle = {
  mounted() {
    if (!window.__buzzModeInitialized) {
      window.__buzzModeState = readBuzzModePreference()
      window.__buzzModeInitialized = true
    }

    const currentState = Boolean(window.__buzzModeState)
    applyBuzzMode(currentState, {suppressAnimation: true})

    this.handleChange = (event) => {
      const nextEnabled = Boolean(event.target.checked)
      if (nextEnabled === Boolean(window.__buzzModeState)) {
        return
      }

      window.__buzzModeState = nextEnabled
      saveBuzzModePreference(nextEnabled)
      applyBuzzMode(nextEnabled)
    }

    this.el.addEventListener("change", this.handleChange)
  },
  destroyed() {
    this.el.removeEventListener("change", this.handleChange)
  }
}

Hooks.DesktopNavState = {
  mounted() {
    applyDesktopNavState(this.readCollapsed())
  },
  updated() {
    applyDesktopNavState(this.readCollapsed())
  },
  destroyed() {
    applyDesktopNavState(false)
  },
  readCollapsed() {
    return this.el.dataset.collapsed === "true"
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300))
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

if (window.navigator.standalone) {
  document.documentElement.style.setProperty("--sat", "env(safe-area-inset-top)")
  document.documentElement.classList.add("standalone")
}
