# BipBuffers (WIP)

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://kiranshila.github.io/BipBuffers.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://kiranshila.github.io/BipBuffers.jl/dev)
[![Build Status](https://github.com/kiranshila/BipBuffers.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/kiranshila/BipBuffers.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/kiranshila/BipBuffers.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/kiranshila/BipBuffers.jl)

The BipBuffer type implements a lock-free circular buffer of fixed capacity
where new items are pushed to the back of the list, overwriting values
in a circular fashion, but gauranteeing contiguous reservations. This type
is thread-safe, as is intended for single producer - single consumer applications.

Each coordination variable is marked `@atomic`, so only single threads can
perform those operations. The writer/sender thread is in charge of
`write` and `watermark` and the reader/receiver is in charge of `read`.

An example usecase would be streaming time domain data and consuming in a sliding window.

## Example
```julia
using BipBuffers
using Base.Threads: @spawn

function producer!(messages, writer::BipBufferWriter{T}) where {T}
    for message ∈ messages
        spin_push!(writer,message)
    end
end

buf_size = 100
num_msg = 40
msg_size = 5
reader,writer = reader_writer(buf_size,UInt8)
messages = [rand(UInt8,msg_size) for _ in 1:num_msg]

# Produce on some thread
@spawn producer!(messages, writer)

# Consume on this thread
sink = zeros(UInt8,msg_size)
for i in 1:num_msg
    spin_pop!(reader,sink)
    @asser sink == messages[i]
end
```