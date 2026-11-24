## 1. Mission and claim ladder

**Mission.** Determine what a single ESP32-S3 — no second inference node — can and cannot infer about humans from Wi-Fi Channel State Information (CSI) obtained in router-ping mode against a stock home router. The headline question is the impressive one:

> **RQ-L3: Can a single ESP32-S3 distinguish a stationary human from an empty room?**

The work is structured as a ladder of three claims. Each rung is a standalone deliverable; failure at a higher rung erases nothing below it.

| Rung | Claim | Evidence status (memo) | Role in thesis |
|---|---|---|---|
| L1 | Detect human motion (walk-through) in the room | Mature in the literature; esp-csi ships a motion/presence demo | Pipeline validation; guaranteed positive baseline |
| L2 | Estimate the breathing rate of a still person at 1–3 m | Demonstrated on single-antenna commodity links (SA-WiSense cross-subcarrier ratios; PulseFi incl. an ESP32-collected dataset) | Strong mid-tier result; supplies features and phase processing for L3 |
| L3 | Stationary human vs. empty room, contactless | Not rigorously demonstrated on ESP32-class hardware; the strongest open-source ESP32 implementation (ESPectre) explicitly refuses to claim it | Thesis centerpiece. Either outcome is publishable |

**Worst case, by design.** If L3 comes back negative, the thesis still holds: L1 lands as a positive result, L2 lands as a characterized positive or quantified negative, and L3 becomes a rigorous boundary analysis (at what distance, posture, duration, and interference level does the signal appear or vanish) — precisely the result the field lacks, made timely by IEEE 802.11bf reaching final approval in 2025. Commercial context confirms the gap: WiZ SpaceSense needs two devices per room and sells motion only.

---