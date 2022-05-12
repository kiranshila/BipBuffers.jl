using BipBuffers
using Test
using Base.Threads: @spawn

function producer!(messages, writer::BipBufferWriter{T}) where {T}
    for message ∈ messages
        spin_push!(writer,message)
    end
end

@testset "BipBuffers.jl" begin
    buf_size = 100
    num_msg = 40
    msg_size = 5
    reader,writer = reader_writer(buf_size,UInt8)
    messages = [rand(UInt8,msg_size) for _ in 1:num_msg]
    sink = zeros(UInt8,msg_size)
    # Produce on some thread
    @spawn producer!(messages, writer)
    # Consume on this thread
    for i in 1:num_msg
        spin_pop!(reader,sink)
        @test sink == messages[i]
    end
end
