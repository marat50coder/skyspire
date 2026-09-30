use crate::signals::RoundReport;

/// Accumulates the multiplier of a single tower run. The formula mirrors the
/// two-branch payout curve the game uses: a well-centred drop pays above 1.00,
/// an edge landing pays a fraction.
pub struct RoundState {
    total_mult: f64,
    blocks: u32,
    started: bool,
    /// Bet remembered from the round-reset signal. Kept so Rust holds the full
    /// round context even before cash-out fires.
    bet: u32,
}

impl Default for RoundState {
    fn default() -> Self {
        // Start with a neutral multiplier so a cash-out that races ahead of
        // the first landed block still returns the bet instead of zero.
        Self {
            total_mult: 1.0,
            blocks: 0,
            started: false,
            bet: 0,
        }
    }
}

impl RoundState {
    pub fn reset(&mut self, bet: u32) {
        self.total_mult = 1.0;
        self.blocks = 0;
        self.started = true;
        self.bet = bet;
    }

    pub fn land(&mut self, accuracy_bp: u32) {
        if !self.started {
            self.total_mult = 1.0;
            self.started = true;
        }
        let accuracy = (accuracy_bp as f64 / 1000.0).clamp(0.0, 1.0);

        let mut mult = if accuracy >= 0.5 {
            let t = (accuracy - 0.5) * 2.0;
            1.0 + t.powf(1.2)
        } else {
            0.5 + accuracy * 0.9
        };
        mult = (mult * 100.0).round() / 100.0;

        self.total_mult = ((self.total_mult * mult) * 10000.0).round() / 10000.0;
        self.blocks += 1;
    }

    pub fn cash_out(&self, bet: u32) -> RoundReport {
        let payout = (bet as f64 * self.total_mult * 100.0).round() / 100.0;
        RoundReport {
            payout,
            total_mult: self.total_mult,
            rating: round_rating(self.blocks, self.total_mult),
            blocks: self.blocks,
        }
    }
}

/// A compact 0..9999 skill score shown on the win banner.
fn round_rating(blocks: u32, total_mult: f64) -> u32 {
    let base = (total_mult * 100.0) as u32;
    (base + blocks.saturating_mul(15)).min(9999)
}
