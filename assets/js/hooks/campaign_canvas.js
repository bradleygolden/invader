/**
 * WorkflowCanvas Hook
 *
 * A vanilla JS hook for the workflow visual editor canvas.
 * Handles drag-and-drop node positioning, edge drawing, pan/zoom, and LiveView event pushing.
 */

const WorkflowCanvas = {
  mounted() {
    this.canvas = this.el
    this.svg = this.el.querySelector('.workflow-edges-svg')
    this.nodesContainer = this.el.querySelector('.workflow-nodes-container')

    // State
    this.nodes = new Map()
    this.edges = new Map()
    this.selectedNode = null
    this.selectedEdge = null
    this.dragState = null
    this.edgeDrawing = null
    this.pan = { x: 0, y: 0 }
    this.zoom = 1

    // Grid settings
    this.gridSize = 20
    this.snapToGrid = true

    // Initialize
    this.setupEventListeners()
    this.loadInitialData()
  },

  destroyed() {
    this.removeEventListeners()
  },

  updated() {
    // Refresh nodes map with current DOM elements
    this.refreshNodes()
    // Re-render edges when nodes update
    this.renderEdges()
  },

  refreshNodes() {
    const nodeElements = this.nodesContainer?.querySelectorAll('.workflow-node') || []
    const currentNodeIds = new Set()

    nodeElements.forEach(el => {
      const id = el.dataset.nodeId
      currentNodeIds.add(id)

      const existingNode = this.nodes.get(id)
      if (existingNode) {
        // Update the element reference, keep the position
        existingNode.el = el
      } else {
        // New node - add to map
        const x = parseFloat(el.dataset.x) || 0
        const y = parseFloat(el.dataset.y) || 0
        this.nodes.set(id, { el, x, y })
        this.updateNodePosition(id, x, y)
      }
    })

    // Remove nodes that are no longer in the DOM
    for (const nodeId of this.nodes.keys()) {
      if (!currentNodeIds.has(nodeId)) {
        this.nodes.delete(nodeId)
        if (this.selectedNode === nodeId) {
          this.selectedNode = null
        }
      }
    }
  },

  setupEventListeners() {
    // Node drag handling
    this.handleMouseDown = this.onMouseDown.bind(this)
    this.handleMouseMove = this.onMouseMove.bind(this)
    this.handleMouseUp = this.onMouseUp.bind(this)
    this.handleKeyDown = this.onKeyDown.bind(this)

    this.canvas.addEventListener('mousedown', this.handleMouseDown)
    document.addEventListener('mousemove', this.handleMouseMove)
    document.addEventListener('mouseup', this.handleMouseUp)
    document.addEventListener('keydown', this.handleKeyDown)

    // Zoom handling
    this.handleWheel = this.onWheel.bind(this)
    this.canvas.addEventListener('wheel', this.handleWheel, { passive: false })

    // Zoom control buttons
    this.handleZoomIn = this.onZoomIn.bind(this)
    this.handleZoomOut = this.onZoomOut.bind(this)
    this.handleZoomSelect = this.onZoomSelect.bind(this)

    this.zoomInBtn = this.el.querySelector('.zoom-in')
    this.zoomOutBtn = this.el.querySelector('.zoom-out')
    this.zoomSelect = this.el.querySelector('.zoom-select')

    this.zoomInBtn?.addEventListener('click', this.handleZoomIn)
    this.zoomOutBtn?.addEventListener('click', this.handleZoomOut)
    this.zoomSelect?.addEventListener('change', this.handleZoomSelect)

    // Context menu prevention
    this.canvas.addEventListener('contextmenu', e => e.preventDefault())
  },

  removeEventListeners() {
    this.canvas.removeEventListener('mousedown', this.handleMouseDown)
    document.removeEventListener('mousemove', this.handleMouseMove)
    document.removeEventListener('mouseup', this.handleMouseUp)
    document.removeEventListener('keydown', this.handleKeyDown)
    this.canvas.removeEventListener('wheel', this.handleWheel)
    this.zoomInBtn?.removeEventListener('click', this.handleZoomIn)
    this.zoomOutBtn?.removeEventListener('click', this.handleZoomOut)
    this.zoomSelect?.removeEventListener('change', this.handleZoomSelect)
  },

  loadInitialData() {
    // Nodes and edges are rendered server-side
    // Parse them from DOM and store in our state
    const nodeElements = this.nodesContainer?.querySelectorAll('.workflow-node') || []
    nodeElements.forEach(el => {
      const id = el.dataset.nodeId
      const x = parseFloat(el.dataset.x) || 0
      const y = parseFloat(el.dataset.y) || 0
      this.nodes.set(id, { el, x, y })
      this.updateNodePosition(id, x, y)
    })

    this.renderEdges()
  },

  onMouseDown(e) {
    const nodeEl = e.target.closest('.workflow-node')
    const portEl = e.target.closest('.workflow-port')
    const isCanvas = e.target === this.canvas || e.target.classList.contains('workflow-canvas-bg')

    if (portEl) {
      // Start drawing an edge
      e.preventDefault()
      e.stopPropagation()
      const nodeId = portEl.closest('.workflow-node').dataset.nodeId
      const portType = portEl.dataset.portType // 'output' or 'input'
      const portIndex = parseInt(portEl.dataset.portIndex) || 0

      if (portType === 'output') {
        const rect = portEl.getBoundingClientRect()
        const canvasRect = this.canvas.getBoundingClientRect()

        this.edgeDrawing = {
          sourceNodeId: nodeId,
          sourcePortIndex: portIndex,
          startX: (rect.left + rect.width / 2 - canvasRect.left - this.pan.x) / this.zoom,
          startY: (rect.top + rect.height / 2 - canvasRect.top - this.pan.y) / this.zoom,
          currentX: 0,
          currentY: 0
        }
      }
    } else if (nodeEl) {
      // Start dragging a node
      e.preventDefault()
      const nodeId = nodeEl.dataset.nodeId
      const node = this.nodes.get(nodeId)

      if (node) {
        this.selectNode(nodeId)

        const rect = this.canvas.getBoundingClientRect()
        this.dragState = {
          nodeId,
          startX: (e.clientX - rect.left - this.pan.x) / this.zoom - node.x,
          startY: (e.clientY - rect.top - this.pan.y) / this.zoom - node.y
        }
      }
    } else if (isCanvas) {
      // Start panning or deselect
      if (e.button === 0) {
        this.deselectAll()

        // Start panning with left click drag on canvas
        this.panState = {
          startX: e.clientX - this.pan.x,
          startY: e.clientY - this.pan.y,
          hasMoved: false
        }
      } else if (e.button === 1) {
        // Middle click also pans
        e.preventDefault()
        this.panState = {
          startX: e.clientX - this.pan.x,
          startY: e.clientY - this.pan.y,
          hasMoved: false
        }
      }
    }
  },

  onMouseMove(e) {
    if (this.dragState) {
      // Dragging a node
      const rect = this.canvas.getBoundingClientRect()
      let x = (e.clientX - rect.left - this.pan.x) / this.zoom - this.dragState.startX
      let y = (e.clientY - rect.top - this.pan.y) / this.zoom - this.dragState.startY

      // Snap to grid
      if (this.snapToGrid) {
        x = Math.round(x / this.gridSize) * this.gridSize
        y = Math.round(y / this.gridSize) * this.gridSize
      }

      // Clamp to positive values
      x = Math.max(0, x)
      y = Math.max(0, y)

      this.updateNodePosition(this.dragState.nodeId, x, y)
      this.renderEdges()
    } else if (this.edgeDrawing) {
      // Drawing a new edge
      const rect = this.canvas.getBoundingClientRect()
      this.edgeDrawing.currentX = (e.clientX - rect.left - this.pan.x) / this.zoom
      this.edgeDrawing.currentY = (e.clientY - rect.top - this.pan.y) / this.zoom
      this.renderTempEdge()
    } else if (this.panState) {
      // Panning the canvas
      this.pan.x = e.clientX - this.panState.startX
      this.pan.y = e.clientY - this.panState.startY
      this.updateTransform()
    }
  },

  onMouseUp(e) {
    if (this.dragState) {
      // End node drag - push position to server
      const node = this.nodes.get(this.dragState.nodeId)
      if (node) {
        this.pushEvent('node_moved', {
          node_id: this.dragState.nodeId,
          x: node.x,
          y: node.y
        })
      }
      this.dragState = null
    }

    if (this.edgeDrawing) {
      // Check if we dropped on an input port
      const portEl = document.elementFromPoint(e.clientX, e.clientY)?.closest('.workflow-port')

      if (portEl && portEl.dataset.portType === 'input') {
        const targetNodeId = portEl.closest('.workflow-node').dataset.nodeId
        const targetPortIndex = parseInt(portEl.dataset.portIndex) || 0

        // Don't allow self-connections
        if (targetNodeId !== this.edgeDrawing.sourceNodeId) {
          this.pushEvent('edge_created', {
            source_node_id: this.edgeDrawing.sourceNodeId,
            source_port_index: this.edgeDrawing.sourcePortIndex,
            target_node_id: targetNodeId,
            target_port_index: targetPortIndex
          })
        }
      }

      this.edgeDrawing = null
      this.clearTempEdge()
    }

    this.panState = null
  },

  onKeyDown(e) {
    // Delete selected node or edge
    if ((e.key === 'Delete' || e.key === 'Backspace') && !e.target.closest('input, textarea')) {
      if (this.selectedNode) {
        this.pushEvent('node_deleted', { node_id: this.selectedNode })
        this.deselectAll()
      } else if (this.selectedEdge) {
        this.pushEvent('edge_deleted', { edge_id: this.selectedEdge })
        this.deselectAll()
      }
    }

    // Escape to deselect
    if (e.key === 'Escape') {
      this.deselectAll()
      if (this.edgeDrawing) {
        this.edgeDrawing = null
        this.clearTempEdge()
      }
    }
  },

  onWheel(e) {
    e.preventDefault()

    if (e.ctrlKey || e.metaKey) {
      // Zoom with Ctrl/Cmd + scroll
      const delta = e.deltaY > 0 ? 0.9 : 1.1
      const newZoom = Math.max(0.25, Math.min(2, this.zoom * delta))

      // Zoom toward mouse position
      const rect = this.canvas.getBoundingClientRect()
      const mouseX = e.clientX - rect.left
      const mouseY = e.clientY - rect.top

      this.pan.x = mouseX - (mouseX - this.pan.x) * (newZoom / this.zoom)
      this.pan.y = mouseY - (mouseY - this.pan.y) * (newZoom / this.zoom)
      this.zoom = newZoom

      this.updateTransform()
    } else {
      // Pan with regular scroll
      this.pan.x -= e.deltaX
      this.pan.y -= e.deltaY
      this.updateTransform()
    }
  },

  onZoomIn(e) {
    e.stopPropagation()
    const zoomLevels = [0.25, 0.50, 0.75, 1, 1.50, 2]
    const currentIndex = zoomLevels.findIndex(z => z >= this.zoom)
    const nextIndex = Math.min(currentIndex + 1, zoomLevels.length - 1)
    this.setZoom(zoomLevels[nextIndex])
  },

  onZoomOut(e) {
    e.stopPropagation()
    const zoomLevels = [0.25, 0.50, 0.75, 1, 1.50, 2]
    const currentIndex = zoomLevels.findIndex(z => z >= this.zoom)
    const prevIndex = Math.max(currentIndex - 1, 0)
    this.setZoom(zoomLevels[prevIndex])
  },

  onZoomSelect(e) {
    e.stopPropagation()
    const newZoom = parseFloat(e.target.value)
    if (!isNaN(newZoom)) {
      this.setZoom(newZoom)
    }
  },

  setZoom(newZoom) {
    // Zoom toward center of canvas
    const rect = this.canvas.getBoundingClientRect()
    const centerX = rect.width / 2
    const centerY = rect.height / 2

    this.pan.x = centerX - (centerX - this.pan.x) * (newZoom / this.zoom)
    this.pan.y = centerY - (centerY - this.pan.y) * (newZoom / this.zoom)
    this.zoom = newZoom

    this.updateTransform()
  },

  updateNodePosition(nodeId, x, y) {
    const node = this.nodes.get(nodeId)
    if (node) {
      node.x = x
      node.y = y
      node.el.style.transform = `translate(${x}px, ${y}px)`
    }
  },

  updateTransform() {
    const container = this.el.querySelector('.workflow-transform-container')
    if (container) {
      container.style.transform = `translate(${this.pan.x}px, ${this.pan.y}px) scale(${this.zoom})`
    }

    // Update zoom select to show current zoom level
    const zoomSelect = this.el.querySelector('.zoom-select')
    if (zoomSelect) {
      const zoomLevels = [0.25, 0.50, 0.75, 1, 1.50, 2]
      const closest = zoomLevels.reduce((prev, curr) =>
        Math.abs(curr - this.zoom) < Math.abs(prev - this.zoom) ? curr : prev
      )
      // Match the option value format (with trailing zeros for decimals)
      const valueMap = { 0.25: '0.25', 0.5: '0.50', 0.75: '0.75', 1: '1', 1.5: '1.50', 2: '2' }
      zoomSelect.value = valueMap[closest] || closest.toString()
    }
  },

  selectNode(nodeId) {
    this.deselectAll()
    this.selectedNode = nodeId
    const node = this.nodes.get(nodeId)
    if (node?.el) {
      node.el.classList.add('selected')
    }
    this.pushEvent('node_selected', { node_id: nodeId })
  },

  selectEdge(edgeId) {
    this.deselectAll()
    this.selectedEdge = edgeId
    const edgePath = this.svg?.querySelector(`[data-edge-id="${edgeId}"]`)
    if (edgePath) {
      edgePath.classList.add('selected')
    }
    this.pushEvent('edge_selected', { edge_id: edgeId })
  },

  deselectAll() {
    if (this.selectedNode) {
      const node = this.nodes.get(this.selectedNode)
      if (node?.el) {
        node.el.classList.remove('selected')
      }
    }
    if (this.selectedEdge) {
      const edgePath = this.svg?.querySelector(`[data-edge-id="${this.selectedEdge}"]`)
      if (edgePath) {
        edgePath.classList.remove('selected')
      }
    }
    this.selectedNode = null
    this.selectedEdge = null
  },

  renderEdges() {
    if (!this.svg) return

    // Get edges from data attributes on the SVG
    const edgesData = JSON.parse(this.svg.dataset.edges || '[]')

    // Clear existing paths except temp edge
    const existingPaths = this.svg.querySelectorAll('path:not(.temp-edge)')
    existingPaths.forEach(p => p.remove())

    // Render each edge
    edgesData.forEach(edge => {
      const sourceNode = this.nodes.get(edge.source_node_id)
      const targetNode = this.nodes.get(edge.target_node_id)

      if (sourceNode && targetNode) {
        const sourcePort = sourceNode.el.querySelector('.workflow-port[data-port-type="output"]')
        const targetPort = targetNode.el.querySelector('.workflow-port[data-port-type="input"]')

        if (sourcePort && targetPort) {
          const path = this.createEdgePath(
            sourceNode.x + sourcePort.offsetLeft + sourcePort.offsetWidth / 2,
            sourceNode.y + sourcePort.offsetTop + sourcePort.offsetHeight / 2,
            targetNode.x + targetPort.offsetLeft + targetPort.offsetWidth / 2,
            targetNode.y + targetPort.offsetTop + targetPort.offsetHeight / 2,
            edge.is_loop_back
          )

          const pathEl = document.createElementNS('http://www.w3.org/2000/svg', 'path')
          pathEl.setAttribute('d', path)
          pathEl.setAttribute('data-edge-id', edge.id)
          pathEl.classList.add('workflow-edge')
          if (edge.is_loop_back) {
            pathEl.classList.add('loop-back')
          }

          pathEl.addEventListener('click', (e) => {
            e.stopPropagation()
            this.selectEdge(edge.id)
          })

          this.svg.appendChild(pathEl)
        }
      }
    })
  },

  createEdgePath(x1, y1, x2, y2, isLoopBack = false) {
    // Create a curved bezier path
    const dx = x2 - x1
    const dy = y2 - y1
    const distance = Math.sqrt(dx * dx + dy * dy)

    // Control point offset based on distance
    const cpOffset = Math.min(distance / 2, 100)

    if (isLoopBack && y2 <= y1) {
      // Loop back: curve around to the side
      const loopOffset = 60
      return `M ${x1} ${y1}
              C ${x1 + cpOffset} ${y1},
                ${x1 + cpOffset} ${y1 - loopOffset},
                ${x1} ${y1 - loopOffset}
              L ${x2} ${y2 - loopOffset}
              C ${x2 - cpOffset} ${y2 - loopOffset},
                ${x2 - cpOffset} ${y2},
                ${x2} ${y2}`
    }

    // Standard downward/forward edge
    return `M ${x1} ${y1} C ${x1} ${y1 + cpOffset}, ${x2} ${y2 - cpOffset}, ${x2} ${y2}`
  },

  renderTempEdge() {
    if (!this.edgeDrawing || !this.svg) return

    let tempPath = this.svg.querySelector('.temp-edge')
    if (!tempPath) {
      tempPath = document.createElementNS('http://www.w3.org/2000/svg', 'path')
      tempPath.classList.add('temp-edge')
      this.svg.appendChild(tempPath)
    }

    const path = this.createEdgePath(
      this.edgeDrawing.startX,
      this.edgeDrawing.startY,
      this.edgeDrawing.currentX,
      this.edgeDrawing.currentY
    )
    tempPath.setAttribute('d', path)
  },

  clearTempEdge() {
    const tempPath = this.svg?.querySelector('.temp-edge')
    if (tempPath) {
      tempPath.remove()
    }
  },

  // Called from LiveView to add a new node at position
  addNode(nodeId, x, y) {
    const nodeEl = this.nodesContainer?.querySelector(`[data-node-id="${nodeId}"]`)
    if (nodeEl) {
      this.nodes.set(nodeId, { el: nodeEl, x, y })
      this.updateNodePosition(nodeId, x, y)
    }
  },

  // Called from LiveView to remove a node
  removeNode(nodeId) {
    this.nodes.delete(nodeId)
    if (this.selectedNode === nodeId) {
      this.selectedNode = null
    }
    this.renderEdges()
  },

  // Called from LiveView to update edges data
  updateEdges(edgesData) {
    if (this.svg) {
      this.svg.dataset.edges = JSON.stringify(edgesData)
      this.renderEdges()
    }
  }
}

export default WorkflowCanvas
