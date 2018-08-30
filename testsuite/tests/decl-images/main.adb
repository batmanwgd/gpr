------------------------------------------------------------------------------
--                                                                          --
--                           GPR2 PROJECT MANAGER                           --
--                                                                          --
--            Copyright (C) 2017, Free Software Foundation, Inc.            --
--                                                                          --
-- This library is free software;  you can redistribute it and/or modify it --
-- under terms of the  GNU General Public License  as published by the Free --
-- Software  Foundation;  either version 3,  or (at your  option) any later --
-- version. This library is distributed in the hope that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE.                            --
--                                                                          --
-- As a special exception under Section 7 of GPL version 3, you are granted --
-- additional permissions described in the GCC Runtime Library Exception,   --
-- version 3.1, as published by the Free Software Foundation.               --
--                                                                          --
-- You should have received a copy of the GNU General Public License and    --
-- a copy of the GCC Runtime Library Exception along with this program;     --
-- see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see    --
-- <http://www.gnu.org/licenses/>.                                          --
--                                                                          --
------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Strings.Fixed;

with GPR2.Context;
with GPR2.Project.Attribute.Set;
with GPR2.Project.Tree;
with GPR2.Project.Variable.Set;
with GPR2.Project.View;

procedure Main is

   use Ada;
   use GPR2;
   use GPR2.Project;

   procedure Display (Prj : Project.View.Object);

   procedure Load (Filename : Name_Type);

   -------------
   -- Display --
   -------------

   procedure Display (Prj : Project.View.Object) is
      use GPR2.Project.Attribute.Set;
      use GPR2.Project.Variable.Set.Set;
   begin
      Text_IO.Put (String (Prj.Name) & " ");
      Text_IO.Set_Col (10);
      Text_IO.Put_Line (Prj.Qualifier'Img);

      if Prj.Has_Attributes then
         Text_IO.New_Line;
         for A of Prj.Attributes loop
            Text_IO.Put_Line (A.Image);
         end loop;

         Text_IO.New_Line;
         for A of Prj.Attributes loop
            Text_IO.Put_Line (A.Image (15));
         end loop;
      end if;

      if Prj.Has_Types then
         Text_IO.New_Line;
         for T of Prj.Types loop
            Text_IO.Put_Line (T.Image);
         end loop;
      end if;

      if Prj.Has_Variables then
         Text_IO.New_Line;
         for V of Prj.Variables loop
            Text_IO.Put_Line (V.Image);
         end loop;

         Text_IO.New_Line;
         for V of Prj.Variables loop
            Text_IO.Put_Line (V.Image (5));
         end loop;
      end if;
   end Display;

   ----------
   -- Load --
   ----------

   procedure Load (Filename : Name_Type) is
      Prj : Project.Tree.Object;
      Ctx : Context.Object;
   begin
      Project.Tree.Load (Prj, Create (Filename), Ctx);
      Display (Prj.Root_Project);

   exception
      when GPR2.Project_Error =>
         if Prj.Has_Messages then
            Text_IO.Put_Line ("Messages found for " & String (Filename));

            for M of Prj.Log_Messages.all loop
               declare
                  Mes : constant String := M.Format;
                  L   : constant Natural :=
                          Strings.Fixed.Index (Mes, "decl-images");
               begin
                  if L /= 0 then
                     Text_IO.Put_Line (Mes (L - 1 .. Mes'Last));
                  else
                     Text_IO.Put_Line (Mes);
                  end if;
               end;
            end loop;

            Text_IO.New_Line;
         end if;
   end Load;

begin
   Load ("demo.gpr");
end Main;