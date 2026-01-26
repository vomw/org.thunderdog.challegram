# rnnoise

set(RNNOISE_DIR "${THIRDPARTY_DIR}/rnnoise")

add_library(rnnoise STATIC
  "${RNNOISE_DIR}/src/celt_lpc.c"
  "${RNNOISE_DIR}/src/denoise.c"
  "${RNNOISE_DIR}/src/kiss_fft.c"
  "${RNNOISE_DIR}/src/pitch.c"
  "${RNNOISE_DIR}/src/rnn.c"
  "${RNNOISE_DIR}/src/rnnoise_tables.c"
  "${RNNOISE_DIR}/src/nnet.c"
  "${RNNOISE_DIR}/src/nnet_default.c"
)
target_include_directories(rnnoise PUBLIC
  "${RNNOISE_DIR}/include"
)