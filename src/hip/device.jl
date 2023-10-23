struct HIPDevice
    device::hipDevice_t
    device_id::Cint
    gcn_arch::String
    wavefront_size::Cint
end

const DEFAULT_DEVICE = Ref{Union{Nothing, HIPDevice}}(nothing)
const ALL_DEVICES = Vector{HIPDevice}()

function HIPDevice(device_id::Integer)
    isempty(ALL_DEVICES) || return ALL_DEVICES[device_id]

    device_ref = Ref{hipDevice_t}()
    hipDeviceGet(device_ref, device_id - 1) |> check

    props = properties(device_id - 1)
    gcn_arch = unsafe_string(pointer([props.gcnArchName...]))
    HIPDevice(device_ref[], device_id, gcn_arch, props.warpSize)
end

device_id(d::HIPDevice) = d.device_id - 1

function stack_size()
    value = Ref{Csize_t}()
    hipDeviceGetLimit(value, hipLimitStackSize) |> check
    value[]
end

function stack_size!(value::Integer)
    hipDeviceSetLimit(hipLimitStackSize, value) |> check
end

function heap_size()
    value = Ref{Csize_t}()
    hipDeviceGetLimit(value, hipLimitMallocHeapSize) |> check
    value[]
end

function heap_size!(value::Integer)
    hipDeviceSetLimit(hipLimitMallocHeapSize, value) |> check
end

Base.hash(dev::HIPDevice, h::UInt) = hash(dev.device, h)

Base.unsafe_convert(::Type{Ptr{T}}, device::HIPDevice) where T =
    reinterpret(Ptr{T}, device.device)

function name(dev::HIPDevice)
    name_vec = zeros(Cuchar, 64)
    hipDeviceGetName(pointer(name_vec), Cint(64), dev.device) |> check
    return strip(String(name_vec), '\0')
end

properties(dev::HIPDevice) = properties(device_id(dev))

function properties(dev_id::Int)
    props_ref = Ref{hipDeviceProp_t}()
    hipGetDeviceProperties(props_ref, dev_id) |> check
    props_ref[]
end

function attribute(dev::HIPDevice, attr)
    v = Ref{Cint}()
    hipDeviceGetAttribute(v, attr, device_id(dev)) |> check
    v[]
end

wavefront_size(d::HIPDevice) = d.wavefront_size

gcn_arch(d::HIPDevice) = d.gcn_arch

function Base.show(io::IO, dev::HIPDevice)
    print(io, "HIPDevice(name=\"$(name(dev))\", id=$(dev.device_id), gcn_arch=$(dev.gcn_arch))")
end

function ndevices()
    count_ref = Ref{Cint}()
    hipGetDeviceCount(count_ref) |> check
    count_ref[]
end

function devices()
    isempty(ALL_DEVICES) || return copy(ALL_DEVICES)

    devs = [HIPDevice(i) for i in 1:ndevices()]
    append!(ALL_DEVICES, devs)
    return devs
end

function device()
    device_id_ref = Ref{Cint}()
    hipGetDevice(device_id_ref) |> check
    return HIPDevice(device_id_ref[] + 1)
end

device!(device::HIPDevice) = hipSetDevice(device_id(device)) |> check

device!(device_id::Integer) = hipSetDevice(device_id - 1) |> check

function device!(f::Base.Callable, device::HIPDevice)
    old_device_id_ref = Ref{Cint}()
    hipGetDevice(old_device_id_ref) |> check
    device!(device)
    try
        f()
    finally
        device!(old_device_id_ref[] + 1)
    end
end

function can_access_peer(dev::HIPDevice, peer::HIPDevice)
    result = Ref{Cint}(0)
    hipDeviceCanAccessPeer(result, device_id(dev), device_id(peer)) |> check
    return result[] == 1
end
