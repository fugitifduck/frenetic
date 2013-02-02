Require Import Word.WordInterface.
Require Import Common.Types.
Require Import Network.Packet.
Require Import OpenFlow.MessagesDef.

Definition get_packet_handler := switchId -> portId -> packet -> unit.

Inductive predicate : Type :=
  | And : predicate -> predicate -> predicate
  | Or : predicate -> predicate -> predicate
  | Not : predicate -> predicate
  | All : predicate
  | NoPackets : predicate
  | Switch : switchId -> predicate
  | InPort : portId -> predicate
  | DlSrc : dlAddr -> predicate
  | DlDst : dlAddr -> predicate.
  (* TODO(arjun): fill in others *)

Inductive action :=
  | To : portId -> action
  | ToAll : action
  | GetPacket : get_packet_handler -> action.

Inductive policy :=
  | Pol : predicate -> list action -> policy
  | Par : policy -> policy -> policy. (** parallel composition *)