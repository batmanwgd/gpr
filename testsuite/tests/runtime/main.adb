------------------------------------------------------------------------------
--                                                                          --
--                           GPR2 PROJECT MANAGER                           --
--                                                                          --
--                     Copyright (C) 2019-2020, AdaCore                     --
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

with Ada.Text_IO;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;

with GPR2.Unit;
with GPR2.Context;
with GPR2.Log;
with GPR2.Context;
with GPR2.Path_Name;
with GPR2.Project.Attribute.Set;
with GPR2.Project.Configuration;
with GPR2.Project.Source.Set;
with GPR2.Project.Tree;
with GPR2.Project.Variable.Set;
with GPR2.Project.View;
with GPR2.Source;

procedure Main is

   use Ada;
   use Ada.Exceptions;
   use GPR2;
   use GPR2.Project;

   procedure Display (Prj : Project.View.Object; Full : Boolean := True);

   procedure Display (Att : Project.Attribute.Object);

   procedure Output_Filename (Filename : Path_Name.Full_Name);
   --  Remove the leading tmp directory

   -------------
   -- Display --
   -------------

   procedure Display (Att : Project.Attribute.Object) is
   begin
      Text_IO.Put ("   " & String (Att.Name.Text));

      if Att.Has_Index then
         Text_IO.Put (" (" & Att.Index.Text & ")");
      end if;

      Text_IO.Put (" ->");

      for V of Att.Values loop
         Text_IO.Put (" " & V.Text);
      end loop;
      Text_IO.New_Line;
   end Display;

   procedure Display (Prj : Project.View.Object; Full : Boolean := True) is
      use GPR2.Project.Attribute.Set;
      use GPR2.Project.Variable.Set.Set;
      K : Natural;
   begin
      Text_IO.Put (String (Prj.Name) & " ");
      Text_IO.Set_Col (10);
      Text_IO.Put_Line (Prj.Qualifier'Img);

      if Full then
         if Prj.Has_Attributes then
            for A in Prj.Attributes.Iterate loop
               Text_IO.Put
                 ("A:   " & String (Attribute.Set.Element (A).Name.Text));
               Text_IO.Put (" ->");

               for V of Element (A).Values loop
                  declare
                     Val : constant GPR2.Value_Type := V.Text;
                  begin
                     K := Strings.Fixed.Index (Val, "adainclude");
                     if K = 0 then
                        K := Strings.Fixed.Index (Val, "adalib");
                     end if;
                     if K = 0 then
                        Text_IO.Put (" " & Val (Val'First .. Val'Last));
                     else
                        Text_IO.Put (" ..." & Val (K - 1 .. Val'Last));
                     end if;
                  end;
               end loop;
               Text_IO.New_Line;
            end loop;
         end if;

         if Prj.Has_Variables then
            for V in Prj.Variables.Iterate loop
               Text_IO.Put ("V:   " & String (Key (V)));
               Text_IO.Put (" -> ");

               declare
                  Val : constant String := Element (V).Value.Text;
               begin
                  K := Strings.Fixed.Index (Val, "adainclude");

                  if K = 0 then
                     Text_IO.Put (Val);
                  else
                     Text_IO.Put ("..." & Val (K - 1 .. Val'Last));
                  end if;
               end;

               Text_IO.New_Line;
            end loop;
         end if;
         Text_IO.New_Line;

         if Prj.Has_Packages then
            for Pck of Prj.Packages loop
               Text_IO.Put_Line (" " & String (Pck.Name));

               if Pck.Has_Attributes then
                  for A of Pck.Attributes loop
                     Display (A);
                  end loop;
               end if;
            end loop;
         end if;
      end if;
   end Display;

   ---------------------
   -- Output_Filename --
   ---------------------

   procedure Output_Filename (Filename : Path_Name.Full_Name) is
      I : constant Positive := Strings.Fixed.Index (Filename, "adainclude");
   begin
      Text_IO.Put (" > " & Filename (I .. Filename'Last));
   end Output_Filename;

   Gpr : constant Path_Name.Object := Create ("demo.gpr");
   Des : constant Configuration.Description :=
           Configuration.Create (Language => "Ada");
   Cnf : constant Configuration.Object :=
           Configuration.Create
             (Configuration.Description_Set'(1 => Des), "all", Gpr);

   Prj : Project.Tree.Object;
   Ctx : Context.Object;

begin
   if Cnf.Has_Messages then
      for M of Cnf.Log_Messages loop
         declare
            F : constant String := M.Sloc.Filename;
            I : constant Natural := Strings.Fixed.Index (F, "runtime");
         begin
            Text_IO.Put_Line ("> " & F (I - 1 .. F'Last));
            Text_IO.Put_Line (M.Level'Img);
            Text_IO.Put_Line (M.Format);
         end;
      end loop;
   end if;

   Project.Tree.Load (Prj, Gpr, Ctx, Config => Cnf);

   Display (Prj.Root_Project);

   if Prj.Has_Configuration then
      Display (Prj.Configuration.Corresponding_View, Full => False);
   end if;

   if Prj.Has_Runtime_Project then
      Display (Prj.Runtime_Project, Full => True);

      for Source of Prj.Runtime_Project.Sources loop
         if Strings.Fixed.Head
           (String (Source.Source.Path_Name.Base_Name), 8) in
           "a-calend" | "a-strunb" | "a-tags  " | "a-calend" | "a-contai"
             | "a-string" | "a-strunb" | "a-tags  " | "a-uncdea" | "ada     "
         then
            declare
               S : constant GPR2.Source.Object := Source.Source;
               U : constant Optional_Name_Type :=
                     (if S.Has_Units then S.Unit_Name else "");
            begin
               Output_Filename (S.Path_Name.Value);

               Text_IO.Set_Col (27);
               Text_IO.Put
                 ("   Kind: " & GPR2.Unit.Kind_Type'Image (S.Kind));
               Text_IO.Put ("   unit: " & String (U));
               Text_IO.New_Line;
            end;
         end if;
      end loop;
   end if;

exception
   when E : GPR2.Project_Error =>
      Text_Io.Put_Line (Exception_Information (E));

      if Prj.Has_Messages then
         Text_IO.Put_Line ("Messages found:");

         for M of Prj.Log_Messages.all loop
            declare
               F : constant String := M.Sloc.Filename;
               I : constant Natural := Strings.Fixed.Index (F, "runtime");
            begin
               Text_IO.Put_Line ("> " & F (I - 1 .. F'Last));
               Text_IO.Put_Line (M.Level'Img);
               Text_IO.Put_Line (M.Format);
            end;
         end loop;
      end if;
end Main;
