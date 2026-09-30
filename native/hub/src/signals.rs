use rinf::{DartSignal, RustSignal};
use serde::{Deserialize, Serialize};

// ── Dart → Rust ─────────────────────────────────────────────

/// A fresh scoring round begins (first bet placed / after a crash or cash-out).
#[derive(Deserialize, DartSignal)]
pub struct RoundReset {
    pub bet: u32,
}

/// A block settled on the tower. `accuracy_bp` is the landing accuracy in
/// permille (0..1000): 1000 = dead-centre, 0 = at the very edge of tolerance.
#[derive(Deserialize, DartSignal)]
pub struct BlockLanded {
    pub accuracy_bp: u32,
}

/// The player closed the round; compute the banked payout for this bet.
#[derive(Deserialize, DartSignal)]
pub struct CashOut {
    pub bet: u32,
}

// ── Rust → Dart ─────────────────────────────────────────────

/// Authoritative round result returned on cash-out.
#[derive(Serialize, RustSignal)]
pub struct RoundReport {
    pub payout: f64,
    pub total_mult: f64,
    pub rating: u32,
    pub blocks: u32,
}
