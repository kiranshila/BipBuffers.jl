module BipBuffers

"""
    BipBuffer{T}(data,capacity::Int)

The BipBuffer type implements a lock-free circular buffer of fixed capacity
where new items are pushed to the back of the list, overwriting values
in a circular fashion, but gauranteeing contiguous reservations. This type
is thread-safe, as is intended for single producer - single consumer applications.

Each coordination variable is marked `@atomic`, so only single threads can
perform those operations. The writer/sender thread is in charge of
`write` and `watermark` and the reader/receiver is in charge of `read`.

Allocate a buffer of elements of type `T` containing items from `data` with
maximum capacity `capacity`.
"""
mutable struct BipBuffer{T} <: AbstractVector{T}
    data::Vector{T}
    capacity::Int
    @atomic read::Int
    @atomic write::Int
    @atomic watermark::Int
    @atomic length::Int
end

# Core Functionality

"""
    push!(bb:BipBuffer,data)

Adds `data` to the buffer `bb`, maintaining alignment
"""
function Base.push!(bb::BipBuffer{T}, data::Vector{T}) where {T}
    @assert length(data) <= bb.capacity
    write_len = length(data)
    write_ptr = @atomic bb.write
    # If write is close to the end, move the watermark to write and
    # wrap around. Don't let write overtake read
    if bb.capacity - write_ptr + 1 >= write_len
        # If we have the space, move watermark fowards
        @atomic bb.watermark = (write_ptr + write_len)
        @atomic bb.write += write_len
        copyto!(view(bb.data, write_ptr:(write_ptr + write_len - 1)), data)
    else
        # Not enough space, wrap around
        @atomic bb.watermark = write_ptr
        @atomic bb.write = (write_len + 1)
        copyto!(view(bb.data, 1:write_len), data)
    end
    @atomic bb.length = min(bb.length + write_len, bb.capacity)
    bb
end

"""
    pop!(bb::BipBuffer,out)

Fetches the last `length(out)` of buffer `bb`, filling preallocated `out`.
If `length(out) > bb.capacity` data will be duplicated.
"""
function Base.pop!(bb::BipBuffer{T}, out::Vector{T}) where {T}
    watermark_ptr = @atomic bb.watermark
    read_ptr = @atomic bb.read
    @inbounds for i in 1:length(out)
        out[i] = bb.data[read_ptr]
        if read_ptr + 1 >= watermark_ptr
            read_ptr = 1
        else
            read_ptr += 1
        end
    end
    # Update read ptr
    @atomic bb.read = read_ptr
    @atomic bb.length = max(bb.length - length(out), 0)
    out
end

"""
    pop!(bb::BipBuffer,len)

Fetches the last `len` elements of buffer `bb`.
"""
function Base.pop!(bb::BipBuffer{T}, len::Int) where {T}
    @assert len <= bb.length
    out = Vector{T}(undef, len)
    pop!(bb, out)
    return out
end

# Compat

function BipBuffer{T}(data::Vector{T}, capacity::Int) where {T}
    @assert length(data) <= capacity
    return BipBuffer{T}(data, capacity, 1, 1, capacity + 1, length(data))
end

function BipBuffer{T}(iter, capacity::Int) where {T}
    vec = copyto!(Vector{T}(undef, capacity), iter)
    return BipBuffer{T}(vec, length(iter))
end

BipBuffer(capacity::Int) = BipBuffer{Any}(capacity)

function BipBuffer{T}(capacity::Int) where {T}
    return BipBuffer{T}(Vector{T}(undef, capacity), capacity, 1, 1, capacity + 1, 0)
end

BipBuffer(iter, capacity::Int) = BipBuffer{eltype(iter)}(iter, capacity)

function BipBuffer{T}(iter) where {T}
    vec = reshape(collect(T, iter), :)
    return BipBuffer{T}(1, length(vec), vec)
end

BipBuffer(iter) = BipBuffer{eltype(iter)}(iter)

"""
    empty!(bb::BipBuffer)

Reset the buffer.
"""
function Base.empty!(cb::BipBuffer)
    @atomic bb.length = 0
    @atomic bb.read = 1
    @atomic bb.write = 1
    @atomic bb.watermark = (bb.capacity + 1)
    return cb
end

Base.eltype(::Type{BipBuffer{T}}) where {T} = T

@inline function _buffer_index(bb::BipBuffer, i::Int)
    read_ptr = @atomic bb.read
    watermark_ptr = @atomic bb.watermark
    idx = read_ptr + i - 1
    if idx >= watermark_ptr
        bb.length - watermark_ptr + read_ptr
    else
        idx
    end
end

Base.@propagate_inbounds function _buffer_index_checked(bb::BipBuffer, i::Int)
    @boundscheck if i < 1 || i > bb.length
        throw(BoundsError(bb, i))
    end
    return _buffer_index(bb, i)
end

"""
    bb[i]
Get the i-th element of BipBuffer.
* `bb[1]` to get the element at the front
* `bb[end]` to get the element at the back
"""
@inline Base.@propagate_inbounds function Base.getindex(bb::BipBuffer, i::Int)
    return bb.data[_buffer_index_checked(bb, i)]
end

"""
    bb[i] = data
Store data to the `i`-th element of `BipBuffer`.
"""
@inline Base.@propagate_inbounds function Base.setindex!(bb::BipBuffer, data, i::Int)
    bb.buffer[_buffer_index_checked(bb, i)] = data
    return cb
end

"""
    length(bb::BipBuffer)
Return the number of elements currently in the buffer.
"""
Base.length(bb::BipBuffer) = bb.length

"""
    size(bb::BipBuffer)
Return a tuple with the size of the buffer.
"""
Base.size(bb::BipBuffer) = (length(bb),)

"""
    isempty(bb::BipBuffer)
Test whether the buffer is empty.
"""
Base.isempty(bb::BipBuffer) = bb.length == 0

""""
    capacity(bb::BipBuffer)
Return capacity of BipBuffer.
"""
capacity(bb::BipBuffer) = bb.capacity

"""
    isfull(bb::BipBuffer)
Test whether the buffer is full.
"""
isfull(bb::BipBuffer) = length(bb) == bb.capacity

struct BipBufferReader{T}
    buffer::BipBuffer{T}
end

struct BipBufferWriter{T}
    buffer::BipBuffer{T}
end

function spin_push!(writer::BipBufferWriter{T}, data::Vector{T}) where {T}
    while true
        if writer.buffer.capacity - (@atomic writer.buffer.length) >= length(data)
            push!(writer.buffer, data)
            break
        end
    end
end

function spin_pop!(reader::BipBufferReader{T}, out::Vector{T}) where {T}
    while true
        if (@atomic reader.buffer.length) >= length(out)
            pop!(reader.buffer, out)
            break
        end
    end
end

function reader_writer(capacity::Int, dtype::DataType=Any)
    buffer = BipBuffer{dtype}(capacity)
    return BipBufferReader(buffer), BipBufferWriter(buffer)
end

export BipBuffer, BipBufferWriter, BipBufferReader, capacity, isfull, spin_push!, spin_pop!,
       reader_writer
end
