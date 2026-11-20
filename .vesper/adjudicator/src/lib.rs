use chess::{Board, Color};
use std::str::FromStr;
static mut INPUT: [u8; 128] = [0;128];
#[no_mangle]
pub extern "C" fn input() -> *mut u8 { core::ptr::addr_of_mut!(INPUT).cast() }
#[no_mangle]
pub extern "C" fn dead(n: usize) -> u32 {
    if n>128 {return 0}
    let data=unsafe {std::slice::from_raw_parts(input(), n)};
    let Ok(fen)=std::str::from_utf8(data) else {return 0};
    let Ok(board)=Board::from_str(fen) else {return 0};
    (chasolver::is_unwinnable_fast(&board,Color::White)
      && chasolver::is_unwinnable_fast(&board,Color::Black)) as u32
}
