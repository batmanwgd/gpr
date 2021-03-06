------------------------------------------------------------------------------
--                                                                          --
--                           GPR2 PROJECT MANAGER                           --
--                                                                          --
--                       Copyright (C) 2019, AdaCore                        --
--                                                                          --
-- This is  free  software;  you can redistribute it and/or modify it under --
-- terms of the  GNU  General Public License as published by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for more details.  You should have received  a copy of the  GNU  --
-- General Public License distributed with GNAT; see file  COPYING. If not, --
-- see <http://www.gnu.org/licenses/>.                                      --
--                                                                          --
------------------------------------------------------------------------------

--  This package is used to store the log messages (error/warning/information)
--  coming from the parser.

with Ada.Iterator_Interfaces;

with GPR2.Containers;
with GPR2.Message;

private with Ada.Containers.Vectors;

package GPR2.Log is

   use type Containers.Count_Type;
   use type Message.Object;

   type Object is tagged private
     with Constant_Indexing => Constant_Reference,
          Variable_Indexing => Reference,
          Default_Iterator  => Iterate,
          Iterator_Element  => Message.Object;

   function Contains
     (Self : Object; Message : GPR2.Message.Object) return Boolean;

   procedure Append (Self : in out Object; Message : GPR2.Message.Object)
     with Post =>
       Self.Count'Old + (if Self.Contains (Message)'Old then 0 else 1)
         = Self.Count;
   --  Insert a log message only if not already present

   function Count (Self : Object) return Containers.Count_Type
     with Post =>
       (if Self.Has_Element then Count'Result > 0 else Count'Result = 0);
   --  Returns the number of message in the log object

   function Is_Empty (Self : Object) return Boolean
     with Post => Self.Count > 0 xor Is_Empty'Result;
   --  Returns True if the log contains no message

   procedure Clear (Self : in out Object)
     with Post => Self.Count = 0;
   --  Removes all message from the log

   function Element
     (Self     : Object;
      Position : Positive) return GPR2.Message.Object
     with Pre => Containers.Count_Type (Position) <= Self.Count;
   --  Returns the message at the given position

   function Has_Element
     (Self        : Object;
      Information : Boolean := True;
      Warning     : Boolean := True;
      Error       : Boolean := True;
      Read        : Boolean := True;
      Unread      : Boolean := True) return Boolean;
   --  Returns True if the log contains some information/warning/error
   --  depending on the value specified.

   function Has_Error (Self : Object) return Boolean;
   --  Returns True if the log contains unread errors

   --  Iterator

   type Cursor is private;

   function Element (Position : Cursor) return Message.Object
     with Post =>
       (if Has_Element (Position)
        then Element'Result.Is_Defined
        else not Element'Result.Is_Defined);

   function Has_Element (Position : Cursor) return Boolean;

   package Log_Iterator is new Ada.Iterator_Interfaces (Cursor, Has_Element);

   type Constant_Reference_Type
     (Message : not null access constant GPR2.Message.Object) is private
     with Implicit_Dereference => Message;

   function Constant_Reference
     (Self     : aliased Object;
      Position : Cursor) return Constant_Reference_Type;

   type Reference_Type
     (Message : not null access GPR2.Message.Object) is private
     with Implicit_Dereference => Message;

   function Reference
     (Self     : aliased in out Object;
      Position : Cursor) return Reference_Type;

   function Iterate
     (Self        : Object;
      Information : Boolean := True;
      Warning     : Boolean := True;
      Error       : Boolean := True;
      Read        : Boolean := True;
      Unread      : Boolean := True)
      return Log_Iterator.Forward_Iterator'Class;
   --  Iterates over all log messages corresponding to the given Filter. The
   --  Unread messages are marked as Read after this call (either explicit call
   --  or using a for-of iterator). Using the Unread flag it is possible to
   --  keep all messages into the list (no need to call Clear) and yet be able
   --  to check for new Unread messages.

private

   package Message_Set is
     new Ada.Containers.Vectors (Positive, Message.Object);

   type Object is tagged record
      Store : aliased Message_Set.Vector;
      Index : Containers.Value_Set;
   end record;

   type Cursor is record
      Store : not null access Message_Set.Vector;
      P     : Natural;
   end record;

   type Constant_Reference_Type
     (Message : not null access constant GPR2.Message.Object) is null record;

   type Reference_Type
     (Message : not null access GPR2.Message.Object) is null record;

   function Contains
     (Self : Object; Message : GPR2.Message.Object) return Boolean
   is
     (Self.Index.Contains (Message.Format));

   function Has_Error (Self : Object) return Boolean is
     (Self.Has_Element
        (Information => False,
         Warning     => False,
         Error       => True,
         Read        => False,
         Unread      => True));

end GPR2.Log;
