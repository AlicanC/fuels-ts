// contract;
script;
dep contract_call;
dep buf;

use std::contract_id::ContractId;
use std::intrinsics::*;
use std::assert::*;
use std::mem::*;
use std::tx::tx_script_data;
use std::option::*;
use std::revert::*;
use std::vec::*;
use buf::*;
use contract_call::*;

struct MulticallCall {
    contract_id: ContractId,
    fn_selector: u64,
    fn_arg: CallValue,
    parameters: CallParameters,
}

// Ideally this would be `main`, but we need to wrap this with some tricks
// since we don't have full Vec support.
fn main_internal(calls: Vec<MulticallCall>) {
    let mut i = 0;
    while i < calls.len() {
        let call = calls.get(i).unwrap();
    
        // Make the call
        call_contract(call.contract_id, call.fn_selector, call.fn_arg, call.parameters);
        
        i = i + 1;
    }
}

enum ScriptCallValue {
    Value: u64,
    Data: (u64, u64),
}

struct ScriptMulticallCall {
    contract_id: ContractId,
    fn_selector: u64,
    fn_arg: ScriptCallValue,
    parameters: CallParameters,
}

struct ScriptData {
    calls: [Option<ScriptMulticallCall>;
    5],
}

fn get_var_data() -> Buffer {
    let ptr = std::tx::tx_script_data_start_pointer();
    let ptr = ptr + __size_of::<ScriptData>();
    let len = std::tx::tx_script_data_length() - __size_of::<ScriptData>();
    ~Buffer::from_ptr(ptr, len)
}

fn ptr_as_vec<T>(ptr: u64, len: u64) -> Vec<T> {
    let vec_len = len / size_of::<T>();
    let vec = (ptr, vec_len, vec_len);
    let vec_ptr = addr_of(vec);
    read(vec_ptr)
}

fn val_as_vec<T, U>(val: T) -> Vec<U> {
    ptr_as_vec(addr_of(val), size_of_val(val))
}

fn buf_addr_of_vec<T>(vec: Vec<T>) -> u64 {
    read(addr_of(vec))
}

fn mem_to_vec(ptr: u64, len: u64) -> Vec<u64> {
    // Calculate capacity, with padding if needed
    let item_len = size_of::<u64>();
    let pad = len % item_len;
    let cap = (len + pad) / item_len;

    // Allocate a vec
    let vec: Vec<u64> = ~Vec::with_capacity(cap);

    // Copy from memory to vec
    let vec_buf_ptr: u64 = buf_addr_of_vec(vec);
    copy(ptr, vec_buf_ptr, len);

    vec
}

fn main(script_data: ScriptData) {
    // TODO: Remove this line when the bug is fixed: https://github.com/FuelLabs/sway/issues/1585
    asm(r1: 0x0000000000000000000000000000000000000000000000000000000000000000) {
    };

    // Our script data is a fixed-size struct followed by a variable-length array of bytes.
    // ScriptData can represent only this fixed-size part,
    // and we will use a RawPointer to access the variable-length part,
    // which contains reference type call arguments' data
    let script_data = tx_script_data::<ScriptData>();
    let var_data = get_var_data();

    // Turn slots into calls
    let call_slots: Vec<Option<ScriptMulticallCall>> = val_as_vec(script_data.calls);
    let mut calls: Vec<MulticallCall> = ~Vec::with_capacity(call_slots.len());
    let mut i = 0;
    while i < call_slots.len() {
        match call_slots.get(i).unwrap() {
            Option::Some(call) => {
                // Prepare the arg
                let fn_arg = match call.fn_arg {
                    ScriptCallValue::Value(val) => CallValue::Value(val), ScriptCallValue::Data((offset, len)) => {
                        let ptr = var_data.ptr() + offset;
                        let vec = mem_to_vec(ptr, len);
                        CallValue::Data(vec)}, 
                };

                let call = MulticallCall {
                    contract_id: call.contract_id,
                    fn_selector: call.fn_selector,
                    fn_arg: fn_arg,
                    parameters: call.parameters,
                };
                calls.push(call);
            },
            _ => {
                // break
                i = call_slots.len();
            }
        }

        // Iterate
        i = i + 1;
    };

    // Call the actual main
    main_internal(calls);
}
