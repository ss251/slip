#include <stddef.h>
#ifndef SLIP_PROVE_FFI_H
#define SLIP_PROVE_FFI_H
#include <stdint.h>
int32_t slip_prove_ping(void);
/* pk_path may be NULL to fall back to runtime keygen (slow; comparison only). */
int32_t slip_prove_circuit(const char *ir_path, const char *params_dir,
                           const char *preimage_path, const char *pk_path,
                           uint64_t *out_keygen_ms, uint64_t *out_prove_ms,
                           uint64_t *out_proof_bytes);
#endif

/* --- Compact runtime natives (JSON over C strings) --- */
uint64_t slip_state_create_with_nulls(const char *descriptor_json);
int32_t  slip_state_set_operation(const char *handle, const char *name);
/* Returns malloc'd JSON; free with slip_free_string. */
char    *slip_contract_query(const char *handle, const char *ops_json, uint64_t block_secs);
void     slip_free_string(char *s);
/* Crypto/bigint natives — JSON strings in, malloc'd JSON/hex strings out (free with slip_free_string). */
char *slip_persistent_hash_aligned(const char *aligned_json);
char *slip_persistent_commit(const char *align_json, const char *value_json, const char *opening_json);
char *slip_value_to_bigint(const char *value_json);   /* returns "0x<hex>" */
char *slip_bigint_to_value(const char *hex_no_prefix);
/* proofData JSON (canonical Node/JSC form) + circuit id → serialised ProofPreimage file for slip_prove_circuit. 0 = ok. */
int32_t  slip_proof_data_into_preimage(const char *proofdata_json, const char *key_location, const char *out_path);
/* proofData JSON → preimage in memory (never on disk) → proof. Proof bytes are malloc'd into *out_proof; free with slip_free_bytes. */
int32_t  slip_prove_proof_data(const char *ir_path, const char *params_dir, const char *proofdata_json,
                               const char *key_location, const char *pk_path,
                               uint64_t *out_keygen_ms, uint64_t *out_prove_ms,
                               uint8_t **out_proof, size_t *out_proof_len);
void     slip_free_bytes(uint8_t *p, size_t len);
/* Binding-aware proving: binding_input_hex (big-endian hex, NULL = no overwrite) is set on the preimage
   exactly as the proof server does before proving. -19 = bad binding hex. */
int32_t  slip_prove_proof_data_bound(const char *ir_path, const char *params_dir, const char *proofdata_json,
                                     const char *key_location, const char *pk_path, const char *binding_input_hex,
                                     uint64_t *out_keygen_ms, uint64_t *out_prove_ms,
                                     uint8_t **out_proof, size_t *out_proof_len);
int32_t  slip_prove_preimage_bound(const char *ir_path, const char *params_dir, const char *preimage_path,
                                   const char *pk_path, const char *binding_input_hex,
                                   uint64_t *out_keygen_ms, uint64_t *out_prove_ms,
                                   uint8_t **out_proof, size_t *out_proof_len);
