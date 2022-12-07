-- sketch
-- v 0.1
--
-- isomorphic keyboard 
-- and pattern recorder 
-- for sketching
--
-- e1     scale
-- k1+e1  root note


--
-- LIBRARIES
--
pattern_time = require 'pattern_time'
musicutil = require 'musicutil'
mxsamples=include("mx.samples/lib/mx.samples")
engine.name="MxSamples"

--
-- DEVICES
--
g = grid.connect()
m = midi.connect()

--
-- VARIABLES
--
PATH = _path.data.."sketch-mxsamples/"
selected_voice = 1
grid_dirty = true
screen_dirty = true
scale_names = {}
for i = 1, #musicutil.SCALES do
  table.insert(scale_names, musicutil.SCALES[i].name)
end
lit = {}
pat_timer = {}



--
-- INIT FUNCTIONS
--
function init_parameters()

  params:add_separator("SKETCH")
  params:add_group("SKETCH - ROUTING",3)
  params:add{
    type="option",
    id="output",
    name="output",
    options={"audio","midi","audio+midi"},
    default=1
  }
  params:add{
    type="number",
    id="note_channel",
    name="midi note channel",
    min=1,
    max=16,
    default=1
  }
  params:add{
    type="number",
    id="cc_channel",
    name="midi cc channel",
    min=1,
    max=16,
    default=2
  }
  params:add_group("SKETCH - KEYBOARD",4)
  params:add{
    type="option",
    id="scale",
    name="scale",
    options=scale_names,
    default=41,
    action=function()
      build_scale()
    end
  }
  params:add{
    type="number",
    id="root_note",
    name="root note",
    min=0,
    max=127,
    default=24,
    formatter=function(param)
      return musicutil.note_num_to_name(param:get(),true)
    end,
    action=function(value)
      build_scale()
    end
  }
  params:add{
    type="number",
    id="velocity",
    name="note velocity",
    min=0,
    max=127,
    default=80
  }
  params:add{
    type="number",
    id="row_interval",
    name="row interval",
    min=1,
    max=12,
    default=5,
    action=function(value)
      build_scale()
    end
  }
  params:bang()
end

function init_mxsamples()
  mx=mxsamples:new()
  instrument_list=mx:list_instruments()
  params:add_group("SKETCH - VOICES",56)
  for i=1,8 do
    params:add_separator("Voice "..i)
    params:add{type="option",id=i.."mx_instrument",name="instrument",options=instrument_list,default=1}
    params:add{type="number",id=i.."mx_velocity",name="velocity",min=0,max=127,default=80}
    params:add{type="control",id=i.."mx_amp",name="amp",controlspec=controlspec.new(0,2,'lin',0.01,0.5,'amp',0.01/2)}
    params:add{type="control",id=i.."mx_pan",name="pan",controlspec=controlspec.new(-1,1,'lin',0,0)}
    params:add{type="control",id=i.."mx_attack",name="attack",controlspec=controlspec.new(0,10,'lin',0,0,'s')}
    params:add{type="control",id=i.."mx_release",name="release",controlspec=controlspec.new(0,10,'lin',0,2,'s')}
  end
  
end


function init_pattern_recorders()
  grid_pattern = {}
  for i=1,8 do
    grid_pattern[i] = pattern_time.new()
    grid_pattern[i].process = grid_note
  end
  active_grid_pattern = 1
end

function init()
  init_parameters()
  init_mxsamples()
  init_pattern_recorders()
  init_pset_callbacks()
  clock.run(grid_redraw_clock)
  clock.run(redraw_clock)
end


--
-- CALLBACK FUNCTIONS
--
function init_pset_callbacks()
  params.action_write = function(filename,name,number)
    local pattern_data = {}
    for i=1,8 do
      local pattern_file = PATH.."sketch-"..number.."_pattern_"..i..".pdata"
      if grid_pattern[i].count > 0 then
        pattern_data[i] = {}
        pattern_data[i].event = grid_pattern[i].event
        pattern_data[i].time = grid_pattern[i].time
        pattern_data[i].count = grid_pattern[i].count
        pattern_data[i].time_factor = grid_pattern[i].time_factor
        tab.save(pattern_data[i],pattern_file)
      else
        if util.file_exists(pattern_file) then
          os.execute("rm "..pattern_file)
        end    
      end
    end
    print("finished writing '"..filename.."' as '"..name.."' and PSET number: "..number)
  end
  
  params.action_read = function(filename,silent,number)
    local pset_file = io.open(filename, "r")
    local pattern_data = {}
    for i=1,8 do
      local pattern_file = PATH.."sketch-"..number.."_pattern_"..i..".pdata"
      if util.file_exists(pattern_file) then
        pattern_data[i] = {}
        grid_pattern[i]:rec_stop()
        grid_pattern[i]:stop()
        grid_pattern[i]:clear()
        pattern_data[i] = tab.load(pattern_file)
        for k,v in pairs(pattern_data[i]) do
          grid_pattern[i][k] = v
        end
      end
    end
    grid_dirty = true
    screen_dirty = true
    print("finished reading '"..filename.."' as PSET number: "..number)
  end
  
  params.action_delete = function(filename,name,number)
    print("finished deleting '"..filename.."' as '"..name.."' and PSET number: "..number)
    for i=1,8 do
      local pattern_file = PATH.."sketch-"..number.."_pattern_"..i..".pdata"
      print(pattern_file)
      if util.file_exists(pattern_file) then
        os.execute("rm "..pattern_file)
      end
    end
  print("finished deleting '"..filename.."' as '"..name.."' and PSET number: "..number)
  end
end


--
-- CLOCK FUNCTIONS
--
function grid_redraw_clock()
  while true do
    clock.sleep(1/30) -- refresh at 30fps.
    if grid_dirty then
      grid_redraw()
      grid_dirty = false
    end
  end
end

function redraw_clock()
  while true do
    clock.sleep(1/30) -- refresh at 30fps.
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
  end
end


--
-- NOTE FUNCTIONS
--
function note_on(voice,note_num)
  if params:get("output") == 1 then
    mx:on(
      {name=params:string(voice.."mx_instrument"),
      midi=note_num,
      velocity=params:get(voice.."mx_velocity"),
      amp=params:get(voice.."mx_amp"),
      pan=params:get(voice.."mx_pan")})
  elseif params:get("output") == 2 then
    m:note_on(note_num, vel)
  elseif params:get("output") == 3 then
    m:note_on(note_num, vel)
    mx:on(
      {name=params:string(voice.."mx_instrument"),
      midi=note_num,
      velocity=params:get(voice.."mx_velocity"),
      amp=params:get(voice.."mx_amp"),
      pan=params:get(voice.."mx_pan")})
  end
end

function note_off(voice,note_num)
  if params:get("output") == 1 then
    mx:off({name=params:string(voice.."mx_instrument"),midi=note_num})
  elseif params:get("output") == 2 then
    m:note_off(note_num)
  elseif params:get("output") == 3 then
    m:note_off(note_num)
    mx:off({name=params:string(voice.."mx_instrument"),midi=note_num})
  end
end

function all_notes_off()
  if params:get("output") == 1 then
    --engine.noteOffAll()
    for k,v in pairs(active_midi_notes) do
      note_off(selected_voice,k)
    end
  elseif params:get("output") == 2 then
    for k,v in pairs(active_midi_notes) do
      note_off(v)
    end
  elseif params:get("output") == 3 then
    engine.noteOffAll()
    for k,v in pairs(active_midi_notes) do
      note_off(v)
    end
  end
end

function clear_lit()
  for i,e in pairs(lit) do
    if e.id == nil and e.pattern == active_grid_pattern then
      print(e.voice.." "..midi_note[e.y][e.x].value)
      note_off(e.voice,midi_note[e.y][e.x].value)
      lit[i] = nil
    end
  end
end


function build_scale()
  if params:get("scale") ~= 41 then
    note_nums = musicutil.generate_scale_of_length(params:get("root_note"),params:get("scale"),112)
  else
    note_nums = {}
    for i=1,112 do
      note_nums[i] = nil
    end
  end

  row_start_note = params:get("root_note")
  note = {}
  for row = 8,1,-1 do
    note_value = row_start_note
    note[row] = {}
    for col = 3,16 do
      note[row][col] = {}
      note[row][col].value = note_value
      for i=1,112 do
        if note[row][col].value == note_nums[i] then
          note[row][col].in_scale = true
        end
      end
      note_value = note_value + 1
    end
    row_start_note = row_start_note + params:get("row_interval")
  end
  grid_dirty = true
end

function grid_note(e)
  --local note = ((7-e.y)*5) + e.x
  if e.state > 0 then
    note_on(e.voice,note[e.y][e.x].value)
    lit[e.id] = {}
    lit[e.id].voice = e.voice
    lit[e.id].pattern = e.pattern
    lit[e.id].x = e.x
    lit[e.id].y = e.y
  else
    if lit[e.id] ~= nil then
      note_off(e.voice,note[e.y][e.x].value)
      lit[e.id] = nil
    end
  end
  grid_redraw()
end


--
-- UI FUNCTIONS
--
function key(n,z)
  if n == 1 then
    shifted = z == 1
  elseif n == 2 and z == 1 then
    selected_voice = util.clamp(selected_voice-1,1,8)
  elseif n == 3 and z == 1 then
    selected_voice = util.clamp(selected_voice+1,1,8)
  end
  screen_dirty = true
end

function enc(n,d)
  if shifted and n == 1 then
    params:delta("root_note",d)
  elseif n == 1 then
    params:delta("scale",d)
  end
  screen_dirty = true
end

function g.key(x,y,z)
  -- pattern recorders
  if x == 1 then
    active_grid_pattern = y
    if z == 1 then
      pattern_rec_press(y)
    end
  elseif x == 2 then
    active_grid_pattern = y
    if z == 1 then
      pat_timer[y] = clock.run(pattern_clear_press,y)
    elseif z == 0 then
      if pat_timer[y] then
        clock.cancel(pat_timer[y])
        pattern_stop_press(y)
      end
    end

  -- notes
  elseif x > 2 then
    local e = {}
    e.id = selected_voice + x*8 + y
    e.voice = selected_voice
    e.pattern = active_grid_pattern
    e.x = x
    e.y = y
    e.state = z
    grid_pattern[active_grid_pattern]:watch(e)
    grid_note(e)
  end
  grid_dirty = true
end

function pattern_clear_press(y)
  clock.sleep(0.5)
  grid_pattern[y]:stop()
  clear_lit()
  --all_notes_off()
  grid_pattern[y]:clear()
  pat_timer[y] = nil
  grid_dirty = true
end

function pattern_stop_press(y)
  --all_notes_off()
  grid_pattern[y]:rec_stop()
  grid_pattern[y]:stop()
  clear_lit()
  grid_dirty = true
end

function pattern_rec_press(y)
  if grid_pattern[y].rec == 0 and grid_pattern[y].count == 0 then
    grid_pattern[y]:stop()
    grid_pattern[y]:rec_start()
  elseif grid_pattern[y].rec == 1 then
    all_notes_off()
    grid_pattern[y]:rec_stop()
    grid_pattern[y]:start()
  elseif grid_pattern[y].play == 1 and grid_pattern[y].overdub == 0 then
    grid_pattern[y]:set_overdub(1)
  elseif grid_pattern[y].play == 1 and grid_pattern[y].overdub == 1 then
    grid_pattern[y]:set_overdub(0)
  elseif grid_pattern[y].play == 0 and grid_pattern[y].count > 0 then
    grid_pattern[y]:start()
  end
  grid_dirty = true
end


--
-- REDRAW FUNCTIONS
--
function redraw()
  screen.clear()
  screen.level(15)

  
  screen.move(0,40)
  screen.text("selected voice: "..selected_voice)
  screen.move(0,60)
  screen.text("scale: "..scale_names[params:get("scale")])
  screen.move(0,50)
  screen.text("root: "..musicutil.note_num_to_name(params:get("root_note"), true))
  screen.update()
end

function grid_redraw()
  g:all(0)
  for y= 1,8 do
    for x= 1,2 do
      if x == 1 then
        if grid_pattern[y].play == 1 and grid_pattern[y].overdub == 1 then
          g:led(x,y,15)
        elseif grid_pattern[y].play == 1 and grid_pattern[y].overdub == 0 then
          g:led(x,y,8)
        elseif grid_pattern[y].rec == 1 then
          g:led(x,y,15)
        else
          g:led(x,y,4)
        end
      elseif x == 2 then
        if grid_pattern[y].count > 0 then
          g:led(x,y,15)
        else
          g:led(x,y,4)
        end
      end
    end
  end

  for x = 3,16 do
    for y = 8,1,-1 do
      -- scale notes
      if note[y][x].in_scale == true then
        g:led(x,y,4)
      end
      -- root notes
      if (note[y][x].value - params:get("root_note")) % 12 == 0 then
        g:led(x,y,8)
      end
    end
  end
  -- lit when pressed
  for i,e in pairs(lit) do
    if e.voice == selected_voice then
      g:led(e.x, e.y,15)
    end
  end
  g:refresh()
end
