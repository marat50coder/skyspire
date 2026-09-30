mod logic;
mod signals;

use std::sync::{Arc, Mutex};

use rinf::{dart_shutdown, DartSignal, RustSignal, write_interface};

use logic::RoundState;
use signals::{BlockLanded, CashOut, RoundReset};

write_interface!();

// The round-scoring engine lives in Rust: Dart reports each landed block and
// asks for the payout at cash-out. Dart never decides the banked amount — the
// native side is the single source of truth for the multiplier and payout.
#[tokio::main(flavor = "current_thread")]
async fn main() {
    let state = Arc::new(Mutex::new(RoundState::default()));

    let reset_state = state.clone();
    tokio::spawn(async move {
        let receiver = RoundReset::get_dart_signal_receiver();
        while let Some(pack) = receiver.recv().await {
            reset_state.lock().unwrap().reset(pack.message.bet);
        }
    });

    let land_state = state.clone();
    tokio::spawn(async move {
        let receiver = BlockLanded::get_dart_signal_receiver();
        while let Some(pack) = receiver.recv().await {
            land_state.lock().unwrap().land(pack.message.accuracy_bp);
        }
    });

    let cash_state = state.clone();
    tokio::spawn(async move {
        let receiver = CashOut::get_dart_signal_receiver();
        while let Some(pack) = receiver.recv().await {
            let report = cash_state.lock().unwrap().cash_out(pack.message.bet);
            report.send_signal_to_dart();
        }
    });

    dart_shutdown().await;
}
