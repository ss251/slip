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
