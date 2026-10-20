/*
 * CZstdDecode — zstd's decode-only single-file library, vendored for Woodcase.
 *
 * zstddeclib.c is generated from the upstream release named in VENDORED.json by
 * build/single_file_libs/create_single_file_decoder.sh; zstd.h and zstd_errors.h are that
 * release's own lib/ headers, unchanged. Only the decompression half of zstd.h is defined:
 * the compressor's declarations have no definitions here, so calling one fails to link.
 * scripts/zstd-upstream checks and refreshes all three files.
 */
#ifndef CZSTDDECODE_H
#define CZSTDDECODE_H

#include "zstd.h"
#include "zstd_errors.h"

#endif /* CZSTDDECODE_H */
