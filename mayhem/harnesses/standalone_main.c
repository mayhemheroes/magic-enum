/* Standalone run-once driver for the magic_enum libFuzzer harness.
 * Reads one input file, hands its bytes to LLVMFuzzerTestOneInput, exits.
 * No libFuzzer runtime — used to replay a single crashing/repro input
 * (built into magic_enum_fuzzer-standalone). */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s <input-file>\n", argv[0]);
    return 1;
  }
  FILE *f = fopen(argv[1], "rb");
  if (!f) {
    fprintf(stderr, "failed to open %s\n", argv[1]);
    return 2;
  }
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (size < 0) {
    fclose(f);
    return 3;
  }
  uint8_t *data = (uint8_t *)malloc((size_t)size + 1);
  if (!data) {
    fclose(f);
    return 4;
  }
  size_t r = size ? fread(data, 1, (size_t)size, f) : 0;
  fclose(f);
  LLVMFuzzerTestOneInput(data, r);
  free(data);
  return 0;
}
