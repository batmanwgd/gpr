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

with Ada.Strings.Unbounded;

package InDash is

   type Instrument is abstract tagged private;

   type Instrument_Reference is access all Instrument;

   type Any_Instrument is access all Instrument'Class;

   function Name (This : access Instrument) return String;

   procedure Set_Name (This : access Instrument; To : String);

   procedure Display (This : access Instrument);

   procedure Update  (This : access Instrument; Millisec : Integer) is abstract;
   --  Update the state of the instrument after millisec has lapsed

private

   use Ada.Strings.Unbounded;

   type Instrument is abstract tagged record
      Name : Unbounded_String;
   end record;

end InDash;
