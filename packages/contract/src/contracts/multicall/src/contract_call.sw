//! Library for calling contracts with unknown ABIs.
library contract_call;

use std::{
    constants::BASE_ASSET_ID,
    context::registers::{context_gas, return_length, return_value},
    contract_id::ContractId,
    intrinsics::size_of,
    mem::{addr_of, copy, read},
    option::Option,
    vec::Vec,
};

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

/// A value passed to or returned from a contract function.
pub enum CallValue {
    Value: u64,
    Data: Vec<u64>,
}

/// Arguments passed to the CALL instruction.
pub struct CallParameters {
    amount: Option<u64>,
    asset_id: Option<ContractId>,
    gas: Option<u64>,
}

impl CallParameters {
    pub fn default() -> CallParameters {
        CallParameters {
            amount: Option::None,
            asset_id: Option::None,
            gas: Option::None,
        }
    }
}

/// Calls the given contract function.
pub fn call_contract(id: ContractId, fn_selector: u64, fn_arg: CallValue, call_parameters: CallParameters) -> CallValue {
    // Prepare the data for the call
    let fn_arg = match fn_arg {
        CallValue::Value(val) => val, CallValue::Data(vec) => buf_addr_of_vec(vec), 
    };
    let call_data = (id, fn_selector, fn_arg);
    let amount = match call_parameters.amount {
        Option::Some(amount) => amount, Option::None => 0, 
    };
    let asset_id = match call_parameters.asset_id {
        Option::Some(id) => id, Option::None => BASE_ASSET_ID, 
    };
    let gas = match call_parameters.gas {
        // Forward gas by the given amount
        Option::Some(gas) => gas, // No limit, so forward all gas available in the context
        Option::None => context_gas(), 
    };

    // Execute the CALL instruction to call the contract
    asm(call_data: call_data, amount: amount, asset_id: asset_id, gas: gas) {
        call call_data amount asset_id gas;
    };

    // Parse the return value
    match return_length() {
        // A copy type was returned with a RET instruction
        0 => {
            let val = return_value();
            CallValue::Value(val)
        },
        // A reference type was returned with a RETD instruction
        len => {
            let ptr = return_value();

            // Copy the return data to a new vec, padding it if necessary
            let item_len = size_of::<u64>();
            let pad = len % item_len;
            let cap = (len + pad) / item_len;
            let vec: Vec<u64> = ~Vec::with_capacity(cap);
            let vec_buf_ptr: u64 = read(addr_of(vec));
            copy(ptr, vec_buf_ptr, len);

            CallValue::Data(vec)
        },
    }
}
