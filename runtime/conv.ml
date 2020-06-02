
exception Wrong_protocol_version of int * int (* max_known, found *)

type ('a, 'hint, 'path) string_reader =
  ?hint:'hint -> ?level:int -> ?path:'path -> Reader.String_reader.t -> 'a

type ('a, 'hint, 'path) io_reader =
  ?hint:'hint -> ?level:int -> ?path:'path -> Reader.IO_reader.t -> 'a

type 'a writer = (Msg_buffer.t -> 'a -> unit)

let get_buf = function
    None -> Msg_buffer.create ()
  | Some b -> Msg_buffer.clear b; b

let serialize ?buf f x =
  let b = get_buf buf in
    f b x;
    Msg_buffer.contents b

let dump f buf x =
  Msg_buffer.clear buf;
  f buf x

let deserialize (f : _ string_reader) ?(offset = 0) s =
  f (Reader.String_reader.make s offset (String.length s - offset))

let serialize_versioned ?buf fs version x =
  let buf = get_buf buf in
    if version < 0 || version > 0xFFFF || version >= Array.length fs then
      invalid_arg ("Extprot.Conv.serialize_versioned: bad version " ^
                   string_of_int version);
    Msg_buffer.add_byte buf (version land 0xFF);
    Msg_buffer.add_byte buf ((version lsr 8) land 0xFF);
    fs.(version) buf x;
    Msg_buffer.contents buf

let deserialize_versioned (fs : _ string_reader array) s =
  let len = String.length s in
    if len < 2 then
      raise (Wrong_protocol_version (Array.length fs, -1));
    let version = Char.code (s.[0]) + (Char.code s.[1] lsl 8) in
      if version < Array.length fs then
        fs.(version) (Reader.String_reader.make s 2 (len - 2))
      else
        raise (Wrong_protocol_version (Array.length fs, version))

let deserialize_versioned' (fs : _ string_reader array) version msg =
  if version >= 0 && version < Array.length fs then
    fs.(version) (Reader.String_reader.make msg 0 (String.length msg))
  else
    raise (Wrong_protocol_version (Array.length fs, version))

let read (f : _ io_reader) io = f (Reader.IO_reader.from_io io)

let write ?buf (f : Msg_buffer.t -> 'a -> unit) io (x : 'a) =
  let buf = get_buf buf in
    f buf x;
    Msg_buffer.output_buffer_to_io io buf

let read_versioned (fs : _ io_reader array) rd =
  let a = Reader.IO_reader.read_byte rd in
  let b = Reader.IO_reader.read_byte rd in
  let version = a + b lsl 8 in
    if version < Array.length fs then
      fs.(version) rd
    else begin
      let hd = Reader.IO_reader.read_prefix rd in
        Reader.IO_reader.skip_value rd hd;
        raise (Wrong_protocol_version ((Array.length fs), version))
    end

let io_read_versioned fs io = read_versioned fs (Reader.IO_reader.from_io io)

let write_versioned ?buf fs version io x =
  let buf = get_buf buf in
    if version < 0 || version > 0xFFFF || version >= Array.length fs then
      invalid_arg ("Extprot.Conv.write_versioned: bad version " ^
                   string_of_int version);
    fs.(version) buf x;
    IO.write_ui16 io version;
    Msg_buffer.output_buffer_to_io io buf

let read_frame io =
  let rd = Reader.IO_reader.from_io io in
  let a = Reader.IO_reader.read_byte rd in
  let b = Reader.IO_reader.read_byte rd in
  let version = a + b lsl 8 in
    (version, Reader.IO_reader.read_message rd)
