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
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/invader"
import topbar from "../vendor/topbar"

const TimezoneDetector = {
  mounted() {
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone
    this.pushEvent("set_user_timezone", {timezone: timezone})
  }
}

const ScrollToBottom = {
  mounted() {
    this.scrollToBottom()
  },
  updated() {
    this.scrollToBottom()
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  }
}

const CopyToClipboard = {
  mounted() {
    this.el.addEventListener('click', (e) => {
      e.preventDefault()
      e.stopPropagation()
      const text = this.el.dataset.clipboardText
      if (text) {
        navigator.clipboard.writeText(text).then(() => {
          this.showToast('Copied to clipboard!')
        }).catch(err => {
          console.error('Failed to copy:', err)
          this.showToast('Failed to copy')
        })
      }
    })
  },

  showToast(message) {
    // Create toast element
    const toast = document.createElement('div')
    toast.className = 'fixed bottom-4 left-1/2 transform -translate-x-1/2 bg-cyan-900 border-2 border-cyan-400 text-cyan-400 px-4 py-2 text-xs z-50 arcade-glow'
    toast.textContent = message
    toast.style.animation = 'fadeInOut 2s ease-in-out forwards'
    document.body.appendChild(toast)

    // Remove after animation
    setTimeout(() => {
      toast.remove()
    }, 2000)
  }
}

const ArcadeAudio = {
  mounted() {
    this.audioContext = null
    this.isPlaying = false
    this.isMuted = localStorage.getItem('arcadeMuted') !== 'false'
    this.timerID = null
    this.stepTime = 0
    this.currentStep = 0
    this.stepDuration = 0.15

    this.updateIcon()

    this.el.addEventListener('click', () => {
      if (!this.audioContext) {
        this.audioContext = new (window.AudioContext || window.webkitAudioContext)()
      }
      this.isMuted = !this.isMuted
      localStorage.setItem('arcadeMuted', this.isMuted)
      this.updateIcon()
      if (this.isMuted) {
        this.stopMusic()
      } else {
        this.startMusic()
      }
    })
  },

  destroyed() {
    this.stopMusic()
    if (this.audioContext) this.audioContext.close()
  },

  updateIcon() {
    const soundOn = this.el.querySelector('.sound-on')
    const soundOff = this.el.querySelector('.sound-off')
    if (soundOn && soundOff) {
      soundOn.classList.toggle('hidden', this.isMuted)
      soundOff.classList.toggle('hidden', !this.isMuted)
    }
  },

  startMusic() {
    if (this.isPlaying) return
    this.isPlaying = true
    this.stepTime = this.audioContext.currentTime
    this.currentStep = 0
    this.scheduleMusic()
  },

  stopMusic() {
    this.isPlaying = false
    if (this.timerID) {
      clearTimeout(this.timerID)
      this.timerID = null
    }
  },

  freq(note, octave) {
    const semitones = { C: 0, 'C#': 1, D: 2, 'D#': 3, E: 4, F: 5, 'F#': 6, G: 7, 'G#': 8, A: 9, 'A#': 10, B: 11 }
    return 440 * Math.pow(2, (semitones[note] - 9) / 12 + (octave - 4))
  },

  scheduleMusic() {
    if (!this.isPlaying || this.isMuted) return

    while (this.stepTime < this.audioContext.currentTime + 0.2) {
      const step = this.currentStep
      const phase = Math.floor(step / 128) % 4
      const localStep = step % 128
      const measure = Math.floor(localStep / 16)
      const beat = localStep % 16

      const sd = this.stepDuration
      const t = this.stepTime

      this.scheduleMarch(t, phase, measure, beat, sd)
      this.scheduleMelody(t, phase, localStep, sd)
      this.scheduleDrone(t, phase, measure, beat, sd)
      this.schedulePercussion(t, phase, beat, sd)

      this.stepTime += sd
      this.currentStep++
    }

    this.timerID = setTimeout(() => this.scheduleMusic(), 40)
  },

  scheduleMarch(t, phase, measure, beat, sd) {
    const marchNotes = [
      [this.freq('A', 2), this.freq('G', 2), this.freq('F', 2), this.freq('E', 2)],
      [this.freq('A', 2), this.freq('G#', 2), this.freq('G', 2), this.freq('F#', 2)],
      [this.freq('E', 2), this.freq('F', 2), this.freq('F#', 2), this.freq('G', 2)],
      [this.freq('A', 2), this.freq('A', 2), this.freq('G', 2), this.freq('G', 2)]
    ]

    const pattern = marchNotes[phase]
    const noteIdx = beat % 4
    const freq = pattern[noteIdx]

    if (beat % 4 === 0) {
      this.playTone(freq, t, sd * 0.7, 'square', 0.07)
      this.playTone(freq * 2, t, sd * 0.4, 'square', 0.02)
    }
  },

  scheduleMelody(t, phase, localStep, sd) {
    const melodies = [
      [[0, 'E', 5], [4, 'D#', 5], [8, 'D', 5], [12, 'C#', 5], [16, 'C', 5], [20, 'B', 4], [24, 'C', 5], [28, 'C#', 5],
       [32, 'D', 5], [36, 'D#', 5], [40, 'E', 5], [44, 'F', 5], [48, 'E', 5], [56, 'D', 5],
       [64, 'C', 5], [68, 'C', 5], [72, 'D', 5], [76, 'E', 5], [80, 'F', 5], [84, 'E', 5], [88, 'D', 5], [92, 'C', 5],
       [96, 'B', 4], [100, 'C', 5], [104, 'D', 5], [108, 'E', 5], [112, 'A', 4], [120, 'A', 4]],
      [[0, 'A', 5], [4, 'G#', 5], [8, 'G', 5], [12, 'F#', 5], [16, 'F', 5], [20, 'E', 5], [24, 'F', 5], [28, 'F#', 5],
       [32, 'G', 5], [40, 'A', 5], [48, 'G', 5], [52, 'F', 5], [56, 'E', 5], [60, 'D', 5],
       [64, 'E', 5], [68, 'E', 5], [72, 'F', 5], [76, 'G', 5], [80, 'A', 5], [88, 'G', 5],
       [96, 'F', 5], [100, 'E', 5], [104, 'D', 5], [108, 'E', 5], [112, 'A', 4], [120, 'E', 5]],
      [[0, 'A', 4], [2, 'C', 5], [4, 'E', 5], [8, 'A', 5], [12, 'G', 5], [16, 'E', 5], [20, 'G', 5], [24, 'A', 5],
       [28, 'G', 5], [32, 'F', 5], [36, 'E', 5], [40, 'D', 5], [44, 'C', 5], [48, 'D', 5], [52, 'E', 5], [56, 'F', 5],
       [64, 'G', 5], [68, 'F', 5], [72, 'E', 5], [76, 'D', 5], [80, 'C', 5], [84, 'D', 5], [88, 'E', 5],
       [96, 'F', 5], [100, 'G', 5], [104, 'A', 5], [112, 'A', 5], [116, 'G', 5], [120, 'E', 5], [124, 'A', 4]],
      [[0, 'E', 5], [2, 'F', 5], [4, 'E', 5], [6, 'D', 5], [8, 'E', 5], [12, 'A', 4],
       [16, 'E', 5], [18, 'F', 5], [20, 'E', 5], [22, 'D', 5], [24, 'C', 5], [28, 'B', 4],
       [32, 'C', 5], [34, 'D', 5], [36, 'C', 5], [38, 'B', 4], [40, 'C', 5], [44, 'E', 5],
       [48, 'A', 5], [52, 'G', 5], [56, 'F', 5], [60, 'E', 5],
       [64, 'D', 5], [66, 'E', 5], [68, 'F', 5], [70, 'E', 5], [72, 'D', 5], [76, 'C', 5],
       [80, 'B', 4], [84, 'C', 5], [88, 'D', 5], [92, 'E', 5],
       [96, 'F', 5], [98, 'E', 5], [100, 'D', 5], [102, 'C', 5], [104, 'B', 4], [108, 'A', 4],
       [112, 'E', 5], [116, 'E', 5], [120, 'A', 4], [124, 'A', 4]]
    ]

    const melody = melodies[phase]
    for (const [pos, note, oct] of melody) {
      if (pos === localStep) {
        this.playTone(this.freq(note, oct), t, sd * 2.5, 'square', 0.045)
        break
      }
    }
  },

  scheduleDrone(t, phase, measure, beat, sd) {
    if (beat !== 0) return

    const droneFreqs = [
      this.freq('A', 2),
      this.freq('G', 2),
      this.freq('F', 2),
      this.freq('E', 2)
    ]

    const baseFreq = droneFreqs[phase]
    const fifth = baseFreq * 1.5

    if (measure % 2 === 0) {
      this.playTone(baseFreq, t, sd * 14, 'sawtooth', 0.02)
      this.playTone(fifth, t, sd * 14, 'triangle', 0.015)
    }
  },

  schedulePercussion(t, phase, beat, sd) {
    if (beat % 8 === 0) {
      this.playNoise(t, sd * 0.08, 0.04)
    }
    if (beat % 8 === 4) {
      this.playNoise(t, sd * 0.05, 0.02)
    }

    if (phase >= 2 && beat % 4 === 2) {
      const freq = 80 + Math.random() * 40
      this.playTone(freq, t, sd * 0.1, 'square', 0.03)
    }

    if (phase === 3 && beat === 0) {
      for (let i = 0; i < 4; i++) {
        const alertFreq = 800 + i * 200
        this.playTone(alertFreq, t + i * 0.05, 0.04, 'square', 0.025)
      }
    }
  },

  playTone(frequency, startTime, duration, waveform, volume) {
    const osc = this.audioContext.createOscillator()
    const gain = this.audioContext.createGain()
    osc.type = waveform
    osc.frequency.setValueAtTime(frequency, startTime)
    gain.gain.setValueAtTime(volume, startTime)
    gain.gain.exponentialRampToValueAtTime(0.001, startTime + duration)
    osc.connect(gain)
    gain.connect(this.audioContext.destination)
    osc.start(startTime)
    osc.stop(startTime + duration + 0.05)
  },

  playNoise(startTime, duration, volume) {
    const bufferSize = this.audioContext.sampleRate * duration
    const buffer = this.audioContext.createBuffer(1, bufferSize, this.audioContext.sampleRate)
    const data = buffer.getChannelData(0)
    for (let i = 0; i < bufferSize; i++) {
      data[i] = Math.random() * 2 - 1
    }
    const noise = this.audioContext.createBufferSource()
    const gain = this.audioContext.createGain()
    const filter = this.audioContext.createBiquadFilter()
    filter.type = 'highpass'
    filter.frequency.value = 5000
    noise.buffer = buffer
    gain.gain.setValueAtTime(volume, startTime)
    gain.gain.exponentialRampToValueAtTime(0.001, startTime + duration)
    noise.connect(filter)
    filter.connect(gain)
    gain.connect(this.audioContext.destination)
    noise.start(startTime)
    noise.stop(startTime + duration)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, TimezoneDetector, ScrollToBottom, ArcadeAudio, CopyToClipboard},
})

// Navigate back in browser history when requested by server
window.addEventListener("phx:navigate-back", (e) => {
  const message = e.detail?.message
  if (message) {
    showToast(message)
  }
  // Navigate immediately - no delay
  if (window.history.length > 1) {
    window.history.back()
  } else {
    window.location.href = "/"
  }
})

function showToast(message) {
  const toast = document.createElement('div')
  toast.className = 'fixed bottom-4 left-1/2 transform -translate-x-1/2 bg-cyan-900 border-2 border-cyan-400 text-cyan-400 px-4 py-2 text-xs z-50 arcade-glow'
  toast.textContent = message
  toast.style.animation = 'fadeInOut 2s ease-in-out forwards'
  document.body.appendChild(toast)
  setTimeout(() => toast.remove(), 2000)
}

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

