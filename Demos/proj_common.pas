unit proj_common;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

uses
  Classes;

{$IFNDEF UNICODE} type
  UnicodeString = WideString; {$ENDIF}

function valExt(str: string; var intVar: int64): boolean; overload;
function valExt(s:PChar; var position:integer; var intVar: int64): boolean; overload;
function valExt(str: string; var realVar: real): boolean; overload;
function valExt(s:PChar; var position:integer; var realVar: real): boolean; overload;

function ExtractFileDirW(const FileName: UnicodeString; Pure: boolean = false)
  : UnicodeString;
function AppPath: UnicodeString;
function AppDir: UnicodeString;

type
  TLinesOption = (loTrim, loNoEmptyLines);
  TLinesOptionSet = set of TLinesOption;

  TUnicodeLines = class
  public
    Options: TLinesOptionSet;
    Lines: array of UnicodeString;
    procedure SetTextStr(const EachString: UnicodeString);
    procedure LoadFromStream(Stream: TStream);
    procedure LoadFromFile(const FileName: string);
  end;

implementation

uses
{$IFNDEF FPC}
  Windows,
{$ELSE}
  LCLIntf, LCLType, LMessages,
{$ENDIF}
  Math, SysUtils;

function valExt(str: string; var intVar: int64): boolean; overload;
var
  position:integer;
begin
  position:=0;
  result:=valExt(PChar(str), position, intVar);
end;

function valExt(s:PChar; var position:integer; var intVar: int64): boolean; overload;
var
  Code: integer;
  sign: boolean;
begin
  while not (s[position] in ['0'..'9',#0]) do inc(position);
  if s[position]=#0 then result:=false
  else
  begin
    Assert(s[position] in ['0'..'9']);
    sign:= (position>0)and(s[position-1]='-');
    intVar:=0;
    while s[position] in ['0'..'9'] do
    begin
      intVar:=intVar*10+ord(s[position])-ord('0');
      inc(position);
    end;
    if sign then intVar:=-intVar;
    result:=true;
  end;
end;

function valExt(str: string; var realVar: real): boolean; overload;
var
  position:integer;
begin
  position:=0;
  result:=valExt(PChar(str), position, realVar);
end;

function valExt(s:PChar; var position:integer; var realVar: real): boolean; overload;
var
  Code: integer;
  sign: integer;
  decfactor: real;
  exponent: int64;
begin
  while not (s[position] in ['0'..'9',#0]) do inc(position);
  if s[position]=#0 then result:=false
  else
  begin
    Assert(s[position] in ['0'..'9']);
    if (position>0)and(s[position-1]='-') then sign:=-1 else sign:=1;
    realVar:=0;
    while s[position] in ['0'..'9'] do
    begin
      realVar:=realVar*10+ord(s[position])-ord('0');
      inc(position);
    end;
    realVar:=sign*realVar;
    if s[position]={$IFNDEF FPC}{$IF RTLVersion>=24.00}FormatSettings.{$IFEND}{$ENDIF}DecimalSeparator then
    begin
      decfactor:=0.1;
      inc(position);
      while s[position] in ['0'..'9'] do
      begin
        realVar:=realVar+sign*(ord(s[position])-ord('0'))*decfactor;
        decfactor:=decfactor/10;
        inc(position);
      end;
    end;
    if s[position] in ['e','E'] then
    begin
      if not valExt(s,position,exponent) then
      begin
        result:=false;
        exit;
      end;
      realVar:=realVar * Power(10,exponent);
    end;
    result:=true;
  end;
end;

  // Default preserve \ at end, if Pure return directory without endig \
// except root dir like c:\ or \
function ExtractFileDirW(const FileName: UnicodeString; Pure: boolean = false)
  : UnicodeString;
var
  pos: integer;
begin
  pos := Length(FileName);
  while (pos > 0) and (FileName[pos] <> PathDelim)
{$IFDEF MSWINDOWS} and (FileName[pos] <> ':'){$ENDIF}
    do
    dec(pos);
  if pos = 0 then
    result := ''
  else
  begin
    Assert((pos >= 1) and ((FileName[pos] = PathDelim){$IFDEF MSWINDOWS} or
      (FileName[pos] = ':'){$ENDIF}));
    if Pure and (pos >= 2)
{$IFDEF MSWINDOWS} and (FileName[pos] = PathDelim) and
      (FileName[pos - 1] <> ':'){$ENDIF}
    then
      SetString(result, PWideChar(FileName), pos - 1)
    else
      SetString(result, PWideChar(FileName), pos);
  end;
end;

function GetModuleFileNameW(hModule: HINST; filename: PWideChar; size: Cardinal): Cardinal;
  stdcall; external 'kernel32.dll';

function AppPath: UnicodeString;
var
  Buffer: array [0 .. MAX_PATH] of WideChar;
  Len: LongWord;
begin
  Len := GetModuleFileNameW(0, Buffer, MAX_PATH);
  Buffer[Len] := #0;
  SetString(result, Buffer, Len);
end;

function AppDir: UnicodeString;
begin
  result := ExtractFileDirW(AppPath());
end;

const
  UTF8BOM: array [0 .. 2] of Byte = ($EF, $BB, $BF);

  { TUnicodeLines }

procedure TUnicodeLines.LoadFromFile(const FileName: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead);
  try
    LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

procedure CheckConstainsZero(SA: AnsiString);
var
  i: integer;
begin
  for i := 1 to Length(SA) do
    if SA[i] = #0 then
    begin
      raise Exception.Create
        ('File has zero, it is binary file or Unicode, must be Latin or UTF8!');
    end;
end;

procedure CheckAbove127(SA: AnsiString);
var
  i: integer;
begin
  for i := 1 to Length(SA) do
    if SA[i] > #127 then
    begin
      raise Exception.Create
        ('File has non latin chars and has not BOM, must be UTF8 with BOM, not Ansi');
    end;
end;

procedure TUnicodeLines.LoadFromStream(Stream: TStream);
var
  ByteOrderMask: array [0 .. 2] of Byte;
  BytesRead: integer;
  Size: int64;
  SA: AnsiString;
  SU: UnicodeString;
begin
  Size := Stream.Size - Stream.Position;
  BytesRead := Stream.Read(ByteOrderMask[0], SizeOf(ByteOrderMask));
  if (BytesRead >= 3) and (ByteOrderMask[0] = UTF8BOM[0]) and
    (ByteOrderMask[1] = UTF8BOM[1]) and (ByteOrderMask[2] = UTF8BOM[2]) then
  begin
    SetLength(SA, (Size - 3) div SizeOf(AnsiChar));
    Stream.Read(SA[1], Size - BytesRead);
    CheckConstainsZero(SA);
    SU := UTF8Decode(SA);
  end
  else
  begin
    SetLength(SA, Size div SizeOf(AnsiChar));
    System.Move(ByteOrderMask[0], SA[1], BytesRead);
    Stream.Read(SA[1 + BytesRead], Size - BytesRead);
    CheckConstainsZero(SA);
    CheckAbove127(SA);
    SU := SA;
  end;
  SetTextStr(SU);
end;

const
  WideNull = WideChar(#0);
  WideLineFeed = WideChar(#10);
  WideCarriageReturn = WideChar(#13);
  WideVerticalTab = WideChar(#11);
  WideFormFeed = WideChar(#12);
  WideLineSeparator = WideChar($2028);
  WideParagraphSeparator = WideChar($2029);

procedure TUnicodeLines.SetTextStr(const EachString: UnicodeString);
var
  Head, Tail: PWideChar;
  LineCnt: integer;
  SU: UnicodeString;
begin
  SetLength(Lines, 0);
  LineCnt := 0;
  Head := PWideChar(EachString);
  while Head^ <> WideNull do
  begin
    Tail := Head;
    while not(Tail^ in [WideNull, WideLineFeed, WideCarriageReturn,
      WideVerticalTab, WideFormFeed]) and (Tail^ <> WideLineSeparator) and
      (Tail^ <> WideParagraphSeparator) do
      Inc(Tail);
    SetString(SU, Head, Tail - Head);
    if loTrim in Options then
      SU := Trim(SU);
    if (SU <> '') or not(loNoEmptyLines in Options) then
    begin
      Inc(LineCnt);
      SetLength(Lines, LineCnt);
      Lines[LineCnt - 1] := SU;
    end;
    Head := Tail;
    if Head^ <> WideNull then
    begin
      Inc(Head);
      if (Tail^ = WideCarriageReturn) and (Head^ = WideLineFeed) then
        Inc(Head);
    end;
  end;
end;

end.
