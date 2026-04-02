# Frontend Visualization System — Distributed Tracing UI

## Purpose

This system provides a **real-time, interactive visualization of distributed request flows** across a multi-cloud architecture.

It is NOT a mock or simulation.

All visual behavior must be driven by **real telemetry data**.

---

## Core Principle

> "If it didn't happen in the system, it must not appear in the UI."

---

## High-Level Architecture

Frontend visualization is composed of:

- UI Renderer (Vite-based app)
- WebSocket client
- Real-time event stream
- Trace-based animation engine

Backend components:

- OpenTelemetry instrumentation
- OpenTelemetry Collector
- Trace Streamer service (custom)

---

## Data Flow

1. User triggers an action
2. Request is sent with trace context
3. Services generate spans (OpenTelemetry)
4. Spans are collected by OpenTelemetry Collector
5. Trace Streamer transforms spans into events
6. Events are streamed via WebSocket
7. Frontend renders animations in real time

---

## Event Model

Events must be simple, normalized, and UI-friendly.

Example:

```json
{
  "trace_id": "abc-123",
  "service": "rds",
  "action": "query",
  "status": "success",
  "duration_ms": 120,
  "timestamp": 1710000000
}
```

---

## Supported Services (Visual Nodes)

Each service must have a visual representation:

- CDN → CloudFront
- API → Kubernetes (EKS / AKS)
- Database → RDS
- Queue → RabbitMQ
- Worker → Kubernetes Pod

---

## Visual Behavior

Each event triggers:

- Node highlight
- Edge animation (flow between nodes)
- State update

---

## Visual States

| State      | Color | Meaning                |
| ---------- | ----- | ---------------------- |
| Processing | Blue  | Request in progress    |
| Success    | Green | Completed successfully |
| Error      | Red   | Failure occurred       |

---

## Animation Rules

- Animations must follow actual event order
- No artificial delays or fake transitions
- Multiple concurrent traces must be supported
- Each trace must be independently visualized

---

## Real-Time Transport

- Protocol: WebSocket
- No polling allowed
- Must support:
  - multiple concurrent clients
  - event streaming per trace_id

---

## Scenarios to Support

### 1. Standard Request Flow

User → CDN → API → DB → Response

---

### 2. Asynchronous Flow

User → API → RabbitMQ → Worker → DB

Must visualize:

- queue depth
- consumer processing

---

### 3. Failure Scenario (Critical)

Simulate:

- API failure (primary cluster down)
- DNS failover to secondary cluster
- degraded latency

UI must show:

- failed requests
- retry attempts
- traffic rerouting

---

## Failure Simulation

The UI must provide:

- a trigger to simulate failure
- visual feedback of system degradation
- recovery visualization

---

## Performance Considerations

- Must handle high event throughput
- Efficient rendering (SVG or Canvas)
- Avoid unnecessary re-renders

---

## Anti-Patterns

- No mocked or fake animations
- No polling-based updates
- No static diagrams without live data
- No overly complex visuals that reduce clarity

---

## UX Principle

> Clarity over visual effects.

The goal is to make distributed systems understandable, not flashy.

---

## End Goal

This system should communicate:

- real-time system behavior
- distributed tracing understanding
- production-level observability skills

It must feel like a live debugging tool for distributed systems.
