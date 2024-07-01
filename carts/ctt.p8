pico-8 cartridge // http://www.pico-8.com
version 42
__lua__

--This version of Celeste Tech Training was modified by Mike Cook 
--Contact:  mike.cook@kcl.ac.uk
--It features less detail and animations to simplify AI TASing.

--~evercore~
--a celeste classic mod base
--v2.2.0

--original game by:
--maddy thorson + noel berry

--major project contributions by
--taco360, meep, gonengazit, and akliant

-- [data structures]

function vector(x,y)
  return {x=x,y=y}
end

function rectangle(x,y,w,h)
  return {x=x,y=y,w=w,h=h}
end

-- [globals]

--tables
objects,got_fruit={},{}
--timers
freeze,delay_restart,sfx_timer,music_timer,ui_timer=0,0,0,0,-99
--camera values
draw_x,draw_y,cam_x,cam_y,cam_spdx,cam_spdy,cam_gain=0,0,0,0,0,0,0.25

-- [entry point]

function _init()
  frames,start_game_flash=0,0
  music(40,0,7)
  lvl_id=0
end

function begin_game()
  max_djump=1
  deaths,frames,seconds,minutes,music_timer,time_ticking,fruit_count,bg_col,cloud_col=0,0,0,0,0,true,0,0,1
  music(0,0,7)
  load_level(1)
end

function is_title()
  return lvl_id==0
end

-- [effects]

clouds={}
for i=0,16 do
  add(clouds,{
    x=rnd"128",
    y=rnd"128",
    spd=1+rnd"4",
  w=32+rnd"32"})
end

particles={}
for i=0,24 do
  add(particles,{
    x=rnd"128",
    y=rnd"128",
    s=flr(rnd"1.25"),
    spd=0.25+rnd"5",
    off=rnd(),
    c=6+rnd"2",
  })
end

dead_particles={}

-- [player entity]



function save_state()
  state = {
    x = player.x,
    y = player.y,
    grace = player.grace,
    input_right = btn(➡️),
    input_left = btn(⬅️),
    input_z = btn(🅾️),
    input_x = btn(❎),
  }
end

function load_state()

end

player={
  layer=2,
  init=function(this)
    this.grace,this.jbuffer=0,0
    this.djump=max_djump
    this.dash_time,this.dash_effect_time=0,0
    this.dash_target_x,this.dash_target_y=0,0
    this.dash_accel_x,this.dash_accel_y=0,0
    this.hitbox=rectangle(1,3,6,5)
    this.spr_off=0
    this.collides=true
    create_hair(this)
  end,

  update=function(this)
    if pause_player then
      return
    end

    -- horizontal input
    local h_input=btn(➡️) and 1 or btn(⬅️) and -1 or 0

    -- spike collision / bottom death
    if spikes_at(this.left(),this.top(),this.right(),this.bottom(),this.spd.x,this.spd.y) or this.y>lvl_ph then
      kill_player(this)
    end

    -- on ground checks
    local on_ground=this.is_solid(0,1)

    -- landing smoke
    -- if on_ground and not this.was_on_ground then
      --this.init_smoke(0,4)
    --end

    -- jump and dash input
    local jump,dash=btn(🅾️) and not this.p_jump,btn(❎) and not this.p_dash
    this.p_jump,this.p_dash=btn(🅾️),btn(❎)

    -- jump buffer
    if jump then
      this.jbuffer=4
    elseif this.jbuffer>0 then
      this.jbuffer-=1
    end

    -- grace frames and dash restoration
    if on_ground then
      this.grace=6
      if this.djump<max_djump then
        psfx"54"
        this.djump=max_djump
      end
    elseif this.grace>0 then
      this.grace-=1
    end

    -- dash effect timer (for dash-triggered events, e.g., berry blocks)
    this.dash_effect_time-=1

    -- dash startup period, accel toward dash target speed
    if this.dash_time>0 then
      --this.init_smoke()
      this.dash_time-=1
      this.spd=vector(appr(this.spd.x,this.dash_target_x,this.dash_accel_x),appr(this.spd.y,this.dash_target_y,this.dash_accel_y))
    else
      -- x movement
      local maxrun=1
      local accel=this.is_ice(0,1) and 0.05 or on_ground and 0.6 or 0.4
      local deccel=0.15

      -- set x speed
      this.spd.x=abs(this.spd.x)<=1 and
      appr(this.spd.x,h_input*maxrun,accel) or
      appr(this.spd.x,sign(this.spd.x)*maxrun,deccel)

      -- facing direction
      if this.spd.x~=0 then
        this.flip.x=this.spd.x<0
      end

      -- y movement
      local maxfall=2

      -- wall slide
      if h_input~=0 and this.is_solid(h_input,0) and not this.is_ice(h_input,0) then
        maxfall=0.4
        -- wall slide smoke
        --if rnd"10"<2 then
          --this.init_smoke(h_input*6)
        --end
      end

      -- apply gravity
      if not on_ground then
        this.spd.y=appr(this.spd.y,maxfall,abs(this.spd.y)>0.15 and 0.21 or 0.105)
      end

      -- jump
      if this.jbuffer>0 then
        if this.grace>0 then
          -- normal jump
          psfx"1"
          this.jbuffer=0
          this.grace=0
          this.spd.y=-2
          --this.init_smoke(0,4)
        else
          -- wall jump
          local wall_dir=(this.is_solid(-3,0) and -1 or this.is_solid(3,0) and 1 or 0)
          if wall_dir~=0 then
            psfx"2"
            this.jbuffer=0
            this.spd=vector(wall_dir*(-1-maxrun),-2)
            if not this.is_ice(wall_dir*3,0) then
              -- wall jump smoke
              --this.init_smoke(wall_dir*6)
            end
          end
        end
      end

      -- dash
      local d_full=5
      local d_half=3.5355339059 -- 5 * sqrt(2)

      if this.djump>0 and dash then
        --this.init_smoke()
        this.djump-=1
        this.dash_time=4
        has_dashed=true
        this.dash_effect_time=10
        -- vertical input
        local v_input=btn(⬆️) and -1 or btn(⬇️) and 1 or 0
        -- calculate dash speeds
        this.spd=vector(h_input~=0 and
          h_input*(v_input~=0 and d_half or d_full) or
          (v_input~=0 and 0 or this.flip.x and -1 or 1)
        ,v_input~=0 and v_input*(h_input~=0 and d_half or d_full) or 0)
        -- effects
        psfx"3"
        freeze=2
        -- dash target speeds and accels
        this.dash_target_x=2*sign(this.spd.x)
        this.dash_target_y=(this.spd.y>=0 and 2 or 1.5)*sign(this.spd.y)
        this.dash_accel_x=this.spd.y==0 and 1.5 or 1.06066017177 -- 1.5 * sqrt()
        this.dash_accel_y=this.spd.x==0 and 1.5 or 1.06066017177
      elseif this.djump<=0 and dash then
        -- failed dash smoke
        psfx"9"
        --this.init_smoke()
      end
    end

    -- animation
    this.spr_off+=0.25
    this.spr = not on_ground and (this.is_solid(h_input,0) and 5 or 3) or  -- wall slide or mid air
    btn(⬇️) and 6 or -- crouch
    btn(⬆️) and 7 or -- look up
    this.spd.x~=0 and h_input~=0 and 1+this.spr_off%4 or 1 -- walk or stand

    -- exit level off the top (except summit)
    if this.y<-4 and levels[lvl_id+1] then
      next_level()
    end

    -- was on the ground
    this.was_on_ground=on_ground
  end,

  draw=function(this)
    -- clamp in screen
    local clamped=mid(this.x,-1,lvl_pw-7)
    if this.x~=clamped then
      this.x=clamped
      this.spd.x=0
    end
      --draw player hair and sprite
      --set_hair_color(this.djump)
      --draw_hair(this)
      --draw_obj_sprite(this)
    
    rectfill(this.x, this.y, this.x+8, this.y+8, 11)
    pal()
  end
}

function create_hair(obj)
  obj.hair={}
  for i=1,5 do
    add(obj.hair,vector(obj.x,obj.y))
  end
end

function set_hair_color(djump)
  pal(8,djump==1 and 8 or djump==2 and 7+frames\3%2*4 or 12)
end

function draw_hair(obj)
  local last=vector(obj.x+(obj.flip.x and 6 or 2),obj.y+(btn(⬇️) and 4 or 3))
  for i,h in ipairs(obj.hair) do
    h.x+=(last.x-h.x)/1.5
    h.y+=(last.y+0.5-h.y)/1.5
    circfill(h.x,h.y,mid(4-i,1,2),8)
    last=h
  end
end

-- [other objects]

player_spawn={
  layer=2,
  init=function(this)
    sfx"4"
    this.spr=3
    this.target=this.y
    this.y=min(this.y+48,lvl_ph)
    cam_x,cam_y=mid(this.x+4,64,lvl_pw-64),mid(this.y,64,lvl_ph-64)
    this.spd.y=-4
    this.state=0
    this.delay=0
    create_hair(this)
    this.djump=max_djump
  end,
  update=function(this)
    destroy_object(this)
    init_object(player,this.x,this.target)
    --[[
    -- jumping up
    if this.state==0 and this.y<this.target+16 then
      this.state=1
      this.delay=3
      -- falling
    elseif this.state==1 then
      this.spd.y+=0.5
      if this.spd.y>0 then
        if this.delay>0 then
          -- stall at peak
          this.spd.y=0
          this.delay-=1
        elseif this.y>this.target then
          -- clamp at target y
          this.y=this.target
          this.spd=vector(0,0)
          this.state=2
          this.delay=5
          --this.init_smoke(0,4)
          sfx"5"
        end
      end
      -- landing and spawning player object
    elseif this.state==2 then
      this.delay-=1
      this.spr=6
      if this.delay<0 then
        
      end
    end
    ]]--
  end,
  draw= player.draw
}

spring={
  init=function(this)
    this.hide_in=0
    this.hide_for=0
  end,
  update=function(this)
    if this.hide_for>0 then
      this.hide_for-=1
      if this.hide_for<=0 then
        this.spr=18
        this.delay=0
      end
    elseif this.spr==18 then
      local hit=this.player_here()
      if hit and hit.spd.y>=0 then
        this.spr=19
        hit.y=this.y-4
        hit.spd.x*=0.2
        hit.spd.y=-3
        hit.djump=max_djump
        this.delay=10
        --this.init_smoke()
        -- crumble below spring
        break_fall_floor(this.check(fall_floor,0,1) or {})
        psfx"8"
      end
    elseif this.delay>0 then
      this.delay-=1
      if this.delay<=0 then
        this.spr=18
      end
    end
    -- begin hiding
    if this.hide_in>0 then
      this.hide_in-=1
      if this.hide_in<=0 then
        this.hide_for=60
        this.spr=0
      end
    end
  end
}

balloon={
  init=function(this)
    this.offset=rnd()
    this.start=this.y
    this.timer=0
    this.hitbox=rectangle(-1,-1,10,10)
  end,
  update=function(this)
    if this.spr==22 then
      this.offset+=0.01
      this.y=this.start+sin(this.offset)*2
      local hit=this.player_here()
      if hit and hit.djump<max_djump then
        psfx"6"
        --this.init_smoke()
        hit.djump=max_djump
        this.spr=0
        this.timer=60
      end
    elseif this.timer>0 then
      this.timer-=1
    else
      psfx"7"
      --this.init_smoke()
      this.spr=22
    end
  end,
  draw=function(this)
    if this.spr==22 then
      for i=7,13 do
        pset(this.x+4+sin(this.offset*2+i/10),this.y+i,6)
      end
      draw_obj_sprite(this)
    end
  end
}

fall_floor={
  init=function(this)
    this.solid_obj=true
    this.state=0
  end,
  update=function(this)
    -- idling
    if this.state==0 then
      for i=0,2 do
        if this.check(player,i-1,-(i%2)) then
          break_fall_floor(this)
        end
      end
    -- shaking
    elseif this.state==1 then
      this.delay-=1
      if this.delay<=0 then
        this.state=2
        this.delay=60--how long it hides for
        this.collideable=false
      end
      -- invisible, waiting to reset
    elseif this.state==2 then
      this.delay-=1
      if this.delay<=0 and not this.player_here() then
        psfx"7"
        this.state=0
        this.collideable=true
        --this.init_smoke()
      end
    end
  end,
  draw=function(this)
    spr(this.state==1 and 26-this.delay/5 or this.state==0 and 23,this.x,this.y) --add an if statement if you use sprite 0 (other stuff also breaks if you do this i think)
  end
}

function break_fall_floor(obj)
  if obj.state==0 then
    psfx"15"
    obj.state=1
    obj.delay=15--how long until it falls
    --obj.init_smoke();
    (obj.check(spring,0,-1) or {}).hide_in=15
  end
end

smoke={
  layer=3,
  init=function(this)
    this.spd=vector(0.3+rnd"0.2",-0.1)
    this.x+=-1+rnd"2"
    this.y+=-1+rnd"2"
    this.flip=vector(rnd()<0.5,rnd()<0.5)
  end,
  update=function(this)
    this.spr+=0.2
    if this.spr>=32 then
      destroy_object(this)
    end
  end
}

fruit={
  check_fruit=true,
  init=function(this)
    this.start=this.y
    this.off=0
  end,
  update=function(this)
    check_fruit(this)
    this.off+=0.025
    this.y=this.start+sin(this.off)*2.5
  end
}

fly_fruit={
  check_fruit=true,
  init=function(this)
    this.start=this.y
    this.step=0.5
    this.sfx_delay=8
  end,
  update=function(this)
    --fly away
    if has_dashed then
      if this.sfx_delay>0 then
        this.sfx_delay-=1
        if this.sfx_delay<=0 then
          sfx_timer=20
          sfx"14"
        end
      end
      this.spd.y=appr(this.spd.y,-3.5,0.25)
      if this.y<-16 then
        destroy_object(this)
      end
      -- wait
    else
      this.step+=0.05
      this.spd.y=sin(this.step)*0.5
    end
    -- collect
    check_fruit(this)
  end,
  draw=function(this)
    spr(26,this.x,this.y)
    for ox=-6,6,12 do
      spr((has_dashed or sin(this.step)>=0) and 45 or this.y>this.start and 47 or 46,this.x+ox,this.y-2,1,1,ox==-6)
    end
  end
}

function check_fruit(this)
  local hit=this.player_here()
  if hit then
    hit.djump=max_djump
    sfx_timer=20
    sfx"13"
    got_fruit[this.fruit_id]=true
    init_object(lifeup,this.x,this.y)
    destroy_object(this)
    if time_ticking then
      fruit_count+=1
    end
  end
end

lifeup={
  init=function(this)
    this.spd.y=-0.25
    this.duration=30
    this.flash=0
  end,
  update=function(this)
    this.duration-=1
    if this.duration<=0 then
      destroy_object(this)
    end
  end,
  draw=function(this)
    this.flash+=0.5
    ?"1000",this.x-4,this.y-4,7+this.flash%2
  end
}

fake_wall={
  check_fruit=true,
  init=function(this)
    this.solid_obj=true
    this.hitbox=rectangle(0,0,16,16)
  end,
  update=function(this)
    this.hitbox=rectangle(-1,-1,18,18)
    local hit=this.player_here()
    if hit and hit.dash_effect_time>0 then
      hit.spd=vector(sign(hit.spd.x)*-1.5,-1.5)
      hit.dash_time=-1
      for ox=0,8,8 do
        for oy=0,8,8 do
          this.init_smoke(ox,oy)
        end
      end
      init_fruit(this,4,4)
    end
    this.hitbox=rectangle(0,0,16,16)
  end,
  draw=function(this)
    sspr(0,32,8,16,this.x,this.y)
    sspr(0,32,8,16,this.x+8,this.y,8,16,true,true)
  end
}

function init_fruit(this,ox,oy)
  sfx_timer=20
  sfx"16"
  init_object(fruit,this.x+ox,this.y+oy,26).fruit_id=this.fruit_id
  destroy_object(this)
end

key={
  update=function(this)
    this.spr=flr(9.5+sin(frames/30))
    if frames==18 then --if spr==10 and previous spr~=10
      this.flip.x=not this.flip.x
    end
    if this.player_here() then
      sfx"23"
      sfx_timer=10
      destroy_object(this)
      has_key=true
    end
  end
}

chest={
  check_fruit=true,
  init=function(this)
    this.x-=4
    this.start=this.x
    this.timer=20
  end,
  update=function(this)
    if has_key then
      this.timer-=1
      this.x=this.start-1+rnd"3"
      if this.timer<=0 then
        init_fruit(this,0,-4)
      end
    end
  end
}

platform={
  layer=0,
  init=function(this)
    this.x-=4
    this.hitbox.w=16
    this.dir=this.spr==11 and -1 or 1
    this.semisolid_obj=true
  end,
  update=function(this)
    this.spd.x=this.dir*0.65
    --screenwrap
    if this.x<-16 then
      this.x=lvl_pw
    elseif this.x>lvl_pw then
      this.x=-16
    end
  end,
  draw=function(this)
    spr(11,this.x,this.y-1,2,1)
  end
}

message={
  layer=1,
  init=function(this)
  if lvl_id==1 then
  this.text="welcome to the tech training#mod, this mod will teach you#a lot of the common tricks#and glitches used in various#celeste mods and speedruns#in the description of this# mod on the cart page in#pico 8, i added a gif of# completion of each room if#you ever get stuck##so to do the first trick, a#spike clip, dash up right#standing on the ground and#you will clip into the spikes#jump immediately after you#see you have your dash back "
    
  elseif lvl_id==2 then
   this.text="for this room, walk up to the#"..
   "wall and jump and up dash,#"..
   "this lines you up so you can#"..
   "walljump off the wall of#"..
   "spikes and hold left to go#"..
   "to the next platform and#"..
   "repeat"
   
   elseif lvl_id==3 then
   this.text="this is called a grace jump.#"..
   "as you spawn in, buffer#"..
   "a dash right off the edge,#"..
   "and jump mid air, you should#"..
   "have your dash back as well#"..
   "as the distance from the dash#"..
   "and jump."
   
   elseif lvl_id==4 then
   this.text="this is another example of a#"..
   "grace jump. this time do a#"..
   "down right dash off the edge#"..
   "and jump. if done right,#"..
   "you will move in the shape#"..
   "of a v and get your dash back"
   
   elseif lvl_id==5 then
   this.text="this is a downward facing#"..
   "spike clip.#"..
   "walk onto the spring and at#"..
   "the peak of your bounce, dash#"..
   "up, and if done right, you#"..
   "will clip through the spikes#"
   
   elseif lvl_id==6 then
   this.text="this is another example of#"..
   "a spike clip.#"..
   "in this spike clip however#"..
   "with this setup, you can#"..
   "walk on the spikes for a#"..
   "few seconds##"..
   "as soon as you spawn in,#"..
   "do a full jump and dash up#"..
   "then waljump and hold right#"..
   "if done right, you should#"..
   "clip into the spikes and be#"..
   "able to walk on them."
   
   elseif lvl_id==7 then
   this.text="these are spike walljumps.#"..
   "sometimes, you can perform#"..
   "a walljump on only left#"..
   "facing spikes. moving into#"..
   "a screen transition or#"..
   "walking against a wall allows#"..
   "this most of the time#"
   
   elseif lvl_id==8 then
   this.text="if you dash off a ledge,#"..
   "depending on how far from#"..
   "the ledge you are, you can#"..
   "get your dash back.#"
   
   elseif lvl_id==9 then
   this.text="you can jump on the corner#"..
   "of spikes if lined up#"..
   "correctly##"..
   "at the beginning of the level#"..
   "jump left against the crumple#"..
   "block and fall. jump when #"..
   "you are on the same level as#"..
   "the spikes on the block below#"..
   "you should jump off the block#"..
   "now hold left and repeat#"  
     
   elseif lvl_id==10 then
   this.text="with a wall side and well#"..
   "timed dash, you can pass#"..
   "under one tile block on the#"..
   "bottom of the screen##"..
   "slide down the wall on the#"..
   "right and as soon as you #"..
   "see yourself clip under the#"..
   "screen a little bit, do a#"..
   "up right dash#"..
   "you should pass under the#"..
   "screen.#"
   
   elseif lvl_id==11 then
   this.text="you can clip into a spike#"..
   "to regain your dash without#"..
   "a perfect line up.##"..
   "as long as you are moving#"..
   "in the direction a spike#"..
   "is pointing, it will not#"..
   "kill you.##"..
   "there are a few ways to get#"..
   "your dash back on this spike#"..
   "taking what was said above,#"..
   "and just waljumping around#"..
   "find something that works for#"..
   "you, it's not too hard to get#"
     
   elseif lvl_id==12 then
   this.text="you can waljump on a wall#"..
   "while approaching from the#"..
   "bottom of it#"..
   "we call this a corner jump#"
    
   elseif lvl_id==13 then
   this.text="the same concept of a#"..
   "corner jump, still applies#"..
   "if the wall has spikes on it##"..
   "jump and dash up right, and#"..
   "aim for the bottom coner of#"..
   "that block with the spikes.#"..
   "as you are directly below#"..
   "that corner, hit the jump#"..
   "button to do a corner jump#"
     
   elseif lvl_id==14 then
   this.text="this is a boost, please#"..
   "watch the gif of this screen#"..
   "if you dont know this tech.#"..
   "to do a boost line yourself#"..
   "up next to the middle#"..
   "platform on the left or#"..
   "right side, jump and dash#"..
   "up to the platform, you want#"..
   "to do a short dash so it#"..
   "ends just as you reach the#"..
   "top of the platform, hold#"..
   "twards the direction of the#"..
   "platform then jump just after#"..
   "you land on the platform#"..
   "if done right, you will jump#"..
   "with more higjht than just#"..
   "jumping off the middle blocks#"
     
   elseif lvl_id==15 then
   this.text="this is another example of a#"..
   "spike clip.#"..
   "you are trying to clip into#"..
   "the spike on that corner to#"..
   "your right.#"..
   "the esaiest way to do this is#"..
   "buffer a right dash then do#"..
   "a grace jump and then up#"..
   "right dash. if done with the#"..
   "correct timing, you should#"..
   "clip into the spike and get#"..
   "your dash back."
     
   elseif lvl_id==16 then
   this.text="this is the same kind of#"..
   "clip as the last room, just#"..
   "a little harder.#"..
   "the same concepts apply.##"..
   "for this clip, you are going#"..
   "to want to up dash parallel#"..
   "to the spikes on the wall,#"..
   "right up next to them, and#"..
   "hold right as your is ending#"..
   "aiming at the corner.#"..
   "if timed correctly, you will#"..
   "clip into the spike, and #"..
   "get your dash back.#"
   
   elseif lvl_id==17 then
   this.text="congratulations!#"..
   "you have completed the#"..
   "tech demo portion of this#"..
   "mod##"..
   "beyond this level, is the#"..
   "final challenge if you wish#"..
   "to proceed......"
   
   elseif lvl_id==18 then
   this.text="this#"..
   "is#"..
   "it##"..
   "welcome to farewell#"..
   "the final screen.#"..
   "combining everything you have#"..
   "learned so far into one final#"..
   "challenge.#"..
   "buckle up and good luck."
     
   elseif lvl_id==19 then
   this.text="completionists so far:#"..
   "lord snek,#"..
   "flyingpenguin223,#"..
   "rav81blaziken,#"..
   "roundupgaming,#"..
   "bacon_good,#"
     
  end
   this.hitbox.x+=4
  end,
  --[[
  draw=function(this)
    if this.player_here() then
      for i,s in ipairs(split(this.text,"#")) do
        camera()
        rectfill(7,7*i,120,7*i+6,7)
        ?s,64-#s*2,7*i+1,0
        camera(draw_x,draw_y)
      end
    end
  end
  ]]--
}

big_chest={
  init=function(this)
    this.state=max_djump>1 and 2 or 0
    this.hitbox.w=16
  end,
  update=function(this)
    if this.state==0 then
      local hit=this.check(player,0,8)
      if hit and hit.is_solid(0,1) then
        music(-1,500,7)
        sfx"37"
        pause_player=true
        hit.spd=vector(0,0)
        this.state=1
        --this.init_smoke()
        this.init_smoke(8)
        this.timer=60
        this.particles={}
      end
    elseif this.state==1 then
      this.timer-=1
      flash_bg=true
      if this.timer<=45 and #this.particles<50 then
        add(this.particles,{
          x=1+rnd"14",
          y=0,
          h=32+rnd"32",
        spd=8+rnd"8"})
      end
      if this.timer<0 then
        this.state=2
        this.particles={}
        flash_bg,bg_col,cloud_col=false,2,14
        init_object(orb,this.x+4,this.y+4,102)
        pause_player=false
      end
    end
  end,
  draw=function(this)
    if this.state==0 then
      draw_obj_sprite(this)
      spr(96,this.x+8,this.y,1,1,true)
    elseif this.state==1 then
      foreach(this.particles,function(p)
        p.y+=p.spd
        line(this.x+p.x,this.y+8-p.y,this.x+p.x,min(this.y+8-p.y+p.h,this.y+8),7)
      end)
    end
    spr(112,this.x,this.y+8)
    spr(112,this.x+8,this.y+8,1,1,true)
  end
}

orb={
  init=function(this)
    this.spd.y=-4
  end,
  update=function(this)
    this.spd.y=appr(this.spd.y,0,0.5)
    local hit=this.player_here()
    if this.spd.y==0 and hit then
      music_timer=45
      sfx"51"
      freeze=10
      destroy_object(this)
      max_djump=2
      hit.djump=2
    end
  end,
  draw=function(this)
    draw_obj_sprite(this)
    for i=0,0.875,0.125 do
      circfill(this.x+4+cos(frames/30+i)*8,this.y+4+sin(frames/30+i)*8,1,7)
    end
  end
}

flag={
  init=function(this)
    this.x+=5
  end,
  update=function(this)
    if not this.show and this.player_here() then
      sfx"55"
      sfx_timer,this.show,time_ticking=30,true,false
    end
  end,
  draw=function(this)
    spr(118+frames/5%3,this.x,this.y)
    if this.show then
      camera()
      rectfill(32,2,96,31,0)
      spr(26,55,6)
      ?"x"..fruit_count,64,9,7
      draw_time(49,16)
      ?"deaths:"..deaths,48,24,7
      camera(draw_x,draw_y)
    end
  end
}

function psfx(num)
  if sfx_timer<=0 then
    sfx(num)
  end
end

-- [tile dict]
tiles={}
foreach(split([[
1,player_spawn
8,key
11,platform
12,platform
18,spring
20,chest
22,balloon
23,fall_floor
26,fruit
45,fly_fruit
64,fake_wall
86,message
96,big_chest
118,flag
]],"\n"),function(t)
 local tile,obj=unpack(split(t))
 tiles[tile]=_ENV[obj]
end)


-- [object functions]

function init_object(type,x,y,tile)
  --generate and check berry id
  local id=x..","..y..","..lvl_id
  if type.check_fruit and got_fruit[id] then
    return
  end

  local obj={
    type=type,
    collideable=true,
    --collides=false,
    spr=tile,
    flip=vector(),--false,false
    x=x,
    y=y,
    hitbox=rectangle(0,0,8,8),
    spd=vector(0,0),
    rem=vector(0,0),
    fruit_id=id,
  }

  function obj.left() return obj.x+obj.hitbox.x end
  function obj.right() return obj.left()+obj.hitbox.w-1 end
  function obj.top() return obj.y+obj.hitbox.y end
  function obj.bottom() return obj.top()+obj.hitbox.h-1 end

  function obj.is_solid(ox,oy)
    for o in all(objects) do
      if o!=obj and (o.solid_obj or o.semisolid_obj and not obj.objcollide(o,ox,0) and oy>0) and obj.objcollide(o,ox,oy) then
        return true
      end
    end
    return obj.is_flag(ox,oy,0) -- solid terrain
  end

  function obj.is_ice(ox,oy)
    return obj.is_flag(ox,oy,4)
  end

  function obj.is_flag(ox,oy,flag)
    for i=max(0,(obj.left()+ox)\8),min(lvl_w-1,(obj.right()+ox)/8) do
      for j=max(0,(obj.top()+oy)\8),min(lvl_h-1,(obj.bottom()+oy)/8) do
        if fget(tile_at(i,j),flag) then
          return true
        end
      end
    end
  end

  function obj.objcollide(other,ox,oy)
    return other.collideable and
    other.right()>=obj.left()+ox and
    other.bottom()>=obj.top()+oy and
    other.left()<=obj.right()+ox and
    other.top()<=obj.bottom()+oy
  end

  function obj.check(type,ox,oy)
    for other in all(objects) do
      if other and other.type==type and other~=obj and obj.objcollide(other,ox,oy) then
        return other
      end
    end
  end

  function obj.player_here()
    return obj.check(player,0,0)
  end

  function obj.move(ox,oy,start)
    for axis in all{"x","y"} do
      obj.rem[axis]+=axis=="x" and ox or oy
      local amt=round(obj.rem[axis])
      obj.rem[axis]-=amt
      local upmoving=axis=="y" and amt<0
      local riding=not obj.player_here() and obj.check(player,0,upmoving and amt or -1)
      local movamt
      if obj.collides then
        local step=sign(amt)
        local d=axis=="x" and step or 0
        local p=obj[axis]
        for i=start,abs(amt) do
          if not obj.is_solid(d,step-d) then
            obj[axis]+=step
          else
            obj.spd[axis],obj.rem[axis]=0,0
            break
          end
        end
        movamt=obj[axis]-p --save how many px moved to use later for solids
      else
        movamt=amt
        if (obj.solid_obj or obj.semisolid_obj) and upmoving and riding then
          movamt+=obj.top()-riding.bottom()-1
          local hamt=round(riding.spd.y+riding.rem.y)
          hamt+=sign(hamt)
          if movamt<hamt then
            riding.spd.y=max(riding.spd.y,0)
          else
            movamt=0
          end
        end
        obj[axis]+=amt
      end
      if (obj.solid_obj or obj.semisolid_obj) and obj.collideable then
        obj.collideable=false
        local hit=obj.player_here()
        if hit and obj.solid_obj then
          hit.move(axis=="x" and (amt>0 and obj.right()+1-hit.left() or amt<0 and obj.left()-hit.right()-1) or 0,
                  axis=="y" and (amt>0 and obj.bottom()+1-hit.top() or amt<0 and obj.top()-hit.bottom()-1) or 0,
                  1)
          if obj.player_here() then
            kill_player(hit)
          end
        elseif riding then
          riding.move(axis=="x" and movamt or 0, axis=="y" and movamt or 0,1)
        end
        obj.collideable=true
      end
    end
  end

  function obj.init_smoke(ox,oy)
    init_object(smoke,obj.x+(ox or 0),obj.y+(oy or 0),29)
  end

  add(objects,obj);

  (obj.type.init or stat)(obj)

  return obj
end

function destroy_object(obj)
  del(objects,obj)
end

function kill_player(obj)
  sfx_timer=12
  sfx"0"
  deaths+=1
  destroy_object(obj)
  --dead_particles={}
  for dir=0,0.875,0.125 do
    add(dead_particles,{
      x=obj.x+4,
      y=obj.y+4,
      t=2,
      dx=sin(dir)*3,
      dy=cos(dir)*3
    })
  end
  delay_restart=1
end

function move_camera(obj)
  cam_spdx=cam_gain*(4+obj.x-cam_x)
  cam_spdy=cam_gain*(4+obj.y-cam_y)

  cam_x+=cam_spdx
  cam_y+=cam_spdy

  --clamp camera to level boundaries
  local clamped=mid(cam_x,64,lvl_pw-64)
  if cam_x~=clamped then
    cam_spdx=0
    cam_x=clamped
  end
  clamped=mid(cam_y,64,lvl_ph-64)
  if cam_y~=clamped then
    cam_spdy=0
    cam_y=clamped
  end
end

-- [level functions]

function next_level()
if lvl_id==6 then
  max_djump=0
elseif lvl_id==7 then
  max_djump=1
elseif lvl_id==8 then
  max_djump=0
elseif lvl_id==9 then
  max_djump=1
elseif lvl_id==11 then
  max_djump=0
elseif lvl_id==12 then
  max_djump=1
elseif lvl_id==17 then
  time_ticking=true
end
  local next_lvl=lvl_id+1

  --check for music trigger
  if music_switches[next_lvl] then
    music(music_switches[next_lvl],500,7)
  end

  load_level(next_lvl)
end

function load_level(id)
  has_dashed,has_key= false--,false


  --remove existing objects
  foreach(objects,destroy_object)

  --reset camera speed
  cam_spdx,cam_spdy=0,0

  local diff_level=lvl_id~=id

  --set level index
  lvl_id=id

  --set level globals
  local tbl=split(levels[lvl_id])
  for i=1,4 do
    _ENV[split"lvl_x,lvl_y,lvl_w,lvl_h"[i]]=tbl[i]*16
  end
  lvl_title=tbl[5]
  lvl_pw,lvl_ph=lvl_w*8,lvl_h*8


  --level title setup
    ui_timer=5

  --reload map
  if diff_level then
    reload()
    --chcek for mapdata strings
    if mapdata[lvl_id] then
      replace_mapdata(lvl_x,lvl_y,lvl_w,lvl_h,mapdata[lvl_id])
    end
  end

  -- entities
  for tx=0,lvl_w-1 do
    for ty=0,lvl_h-1 do
      local tile=tile_at(tx,ty)
      if tiles[tile] then
        init_object(tiles[tile],tx*8,ty*8,tile)
      end
    end
  end
end

-- [main update loop]

function _update()
  if(is_title()) then
    begin_game()
    return
  end

  frames+=1
  if time_ticking then
    seconds+=frames\30
    minutes+=seconds\60
    seconds%=60
  end
  frames%=30

  if music_timer>0 then
    music_timer-=1
    if music_timer<=0 then
      music(10,0,7)
    end
  end

  if sfx_timer>0 then
    sfx_timer-=1
  end

  -- cancel if freeze
  if freeze>0 then
    freeze-=1
    return
  end

  -- restart (soon)
  if delay_restart>0 then
    cam_spdx,cam_spdy=0,0
    delay_restart-=1
    if delay_restart==0 then
      load_level(lvl_id)
    end
  end

  -- update each object
  foreach(objects,function(obj)
    obj.move(obj.spd.x,obj.spd.y,0);
    (obj.type.update or stat)(obj)
  end)

  --move camera to player
  foreach(objects,function(obj)
    if obj.type==player or obj.type==player_spawn then
      move_camera(obj)
    end
  end)

  -- start game
  if is_title() then
    if start_game then
      start_game_flash-=1
      if start_game_flash<=-30 then
        begin_game()
      end
    elseif btn(🅾️) or btn(❎) then
      music"-1"
      start_game_flash,start_game=50,true
      sfx"38"
    end
  end
end

-- [drawing functions]

function _draw()
  if freeze>0 then
    return
  end

  -- reset all palette values
  pal()

  -- start game flash
  if is_title() then
    if start_game then
    	for i=1,15 do
        pal(i, start_game_flash<=10 and ceil(max(start_game_flash)/5) or frames%10<5 and 7 or i)
    	end
    end

    cls()

    -- credits
    sspr(unpack(split"72,32,56,32,36,20"))
    ?"🅾️/❎",55,57,5
    ?"mod by raptite",37,67,8
    ?"special thanks to",31,78,6
    ?"flyingpenguin223, acedic,",18,85,5
    ?"lord snek, chillspider and the",5,91,5
    ?"rest of the celeste classic",11,97,5
    ?"discord, discord.gg/9dm3ncs",11,103,5  
    ?"original game by",34,114,6
    ?"maddy thorson + noel berry",12,122,5

    -- particles
  		-- foreach(particles,draw_particle)

    return
  end

  -- draw bg color
  cls(flash_bg and frames/5 or bg_col)

  -- bg clouds effect
  foreach(clouds,function(c)
    c.x+=c.spd-cam_spdx
    --rectfill(c.x,c.y,c.x+c.w,c.y+16-c.w*0.1875,cloud_col)
    if c.x>128 then
      c.x=-c.w
      c.y=rnd"120"
    end
  end)

  --set cam draw position
  draw_x=round(cam_x)-64
  draw_y=round(cam_y)-64
  camera(draw_x,draw_y)

  -- draw bg terrain
  map(lvl_x,lvl_y,0,0,lvl_w,lvl_h,4)

  --set draw layering
  --0: background layer
  --1: default layer
  --2: player layer
  --3: foreground layer
  local layers={{},{},{}}
  foreach(objects,function(o)
    if o.type.layer==0 then
      draw_object(o) --draw below terrain
    else
      add(layers[o.type.layer or 1],o) --add object to layer, default draw below player
    end
  end)

  -- draw terrain
  map(lvl_x,lvl_y,0,0,lvl_w,lvl_h,2)

  -- draw objects
  foreach(layers,function(l)
    foreach(l,draw_object)
  end)

  -- particles
  -- foreach(particles,draw_particle)

  -- dead particles
  foreach(dead_particles,function(p)
    p.x+=p.dx
    p.y+=p.dy
    p.t-=0.2
    if p.t<=0 then
      del(dead_particles,p)
    end
    --rectfill(p.x-p.t,p.y-p.t,p.x+p.t,p.y+p.t,14+5*p.t%2)
  end)

  -- draw level title
  camera()
  if ui_timer>=-30 then
    --if ui_timer<0 then
      --draw_ui()
    --end
    ui_timer-=1
  end
end

function draw_particle(p)
	p.x+=p.spd-cam_spdx
 p.y+=sin(p.off)-cam_spdy
 p.off+=min(0.05,p.spd/32)
 --rectfill(p.x+draw_x,p.y%128+draw_y,p.x+p.s+draw_x,p.y%128+p.s+draw_y,p.c)
 if p.x>132 then
   p.x=-4
   p.y=rnd"128"
 elseif p.x<-4 then
   p.x=128
   p.y=rnd"128"
 end
end

function draw_object(obj)
  (obj.type.draw or draw_obj_sprite)(obj)
end

function draw_obj_sprite(obj)
  spr(obj.spr,obj.x,obj.y,1,1,obj.flip.x,obj.flip.y)
end

function draw_time(x,y)
  rectfill(x,y,x+32,y+6,0)
  ?two_digit_str(minutes\60)..":"..two_digit_str(minutes%60)..":"..two_digit_str(seconds),x+1,y+1,7
end

function draw_ui()
  rectfill(24,58,104,70,0)
  local title=lvl_title or lvl_id.."00 m"
  ?title,64-#title*2,62,7
  draw_time(4,4)
end

function two_digit_str(x)
  return x<10 and "0"..x or x
end

-- [helper functions]

function round(x)
  return flr(x+0.5)
end

function appr(val,target,amount)
  return val>target and max(val-amount,target) or min(val+amount,target)
end

function sign(v)
  return v~=0 and sgn(v) or 0
end

function tile_at(x,y)
  return mget(lvl_x+x,lvl_y+y)
end

function spikes_at(x1,y1,x2,y2,xspd,yspd)
  for i=max(0,x1\8),min(lvl_w-1,x2/8) do
    for j=max(0,y1\8),min(lvl_h-1,y2/8) do
      if({[17]=y2%8>=6 and yspd>=0,
          [27]=y1%8<=2 and yspd<=0,
          [43]=x1%8<=2 and xspd<=0,
          [59]=x2%8>=6 and xspd>=0})[tile_at(i,j)] then
            return true
      end
    end
  end
end

-->8
--[map metadata]

--@begin
--level table
--"x,y,w,h,title"
levels={
  "0,0,1,1,sPIKE cLIP",
  "1,0,1,1.8125,sPIKE JUMPS",
  "2,0,1,1,gRACE jUMPS",
  "3,0,1,1,gRACE JUMPS v2",
  "4,0,1,1,dOWNWARD sPIKE cLIP",
  "5,0,1,1,sPIKE cLIP + wALK",
  "6,0,1,1,sPIKE wALJUMPS",
  "0,1,1,1,gRACE dASHES",
  "2,1,1,1,sPIKE cORNER jUMPS",
  "3,1,1,1,uNDER sCREEN pASS",
  "4,1,1,1,uNDER sCREEN + cLIP",
  "5,1,1,1,cORNER jUMPS",
  "6,1,1,1,sPIKED cORNER jUMPS",
  "0,2,1,1,bOOST",
  "1,2,1,1,sPIKE cLIP hARD",
  "0,3,1,1,sPIKE cLIP hARDER",
  "1,3,1,1,tHE eND?",
  "2,2,5,2,fAREWELL",
  "7,1.75,1,2.25,vOVO E vOVO"
}

--mapdata string table
--assigned levels will load from here instead of the map
mapdata={
  [17] = "00626363636363636363636363636400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000076000000000000000000000000000000212300000000000000000000000000212525230000000000000000000000213232323223000000000000000000213343434343312300000000000000003042535353534430000000000000002125520000000054252300000000003432325200464700543133000000010000000000005657007171717171002222222223626363636364212222222225252525252222222222222525252525",
  [19] = "012a392a392a392a293a293a293a293a73737373737374393a72737373737373392a392a392a392a293a293a293a293a2a392a392a392a393a293a293a293a29392a392a392a392a293a293a293a293a2a392a392a392a393a293a293a293a29392a392a392a392a293a293a293a293a2a392a392a392a393a293a293a293a29392a392a392a392a293a293a293a293a2a392a392a392a393a293a293a293a29392a392a392a392a293a293a293a293a2a392a392a392a393a293a293a293a29392a392a392a392a293a293a293a293a2a392a392a392a393a293a293a293a29392a392a392a392a293a293a293a293a2a392a392a392a393a293a293a293a29392a392a392a392a293a293a293a293a2a392a392a392a393a293a293a293a29392a392a392a392a293a293a293a293a2a392a392a392a393a293a293a293a29392a392a392a392a293a293a293a293a2a392a392a392a393a293a293a293a29392a392a392a392a293a293a293a293a2a392a392a392a393a293a293a293a29002a392a392a392a293a293a293a290000002a392a392a393a293a293a2900000000002a392a392a293a293a29000000000000002a392a393a293a290000000000000000002a392a293a2900000000000000000000002a393a29000000000000000000000000002a29000000000000000000000000000000000000000000000000000000000000464700000000000000000076000000005657000000000000002222222223004243434400212222222225252525260052535354002425252525"
}

--list of music switch triggers
--assigned levels will start the tracks set here
music_switches={}

--@end

--replace mapdata with hex
function replace_mapdata(x,y,w,h,data)
  for i=1,#data,2 do
    mset(x+i\2%w,y+i\2\w,"0x"..sub(data,i,i+1))
  end
end

--[[

short on tokens?
everything below this comment
is just for grabbing data
rather than loading it
and can be safely removed!

--]]

--copy mapdata string to clipboard
function get_mapdata(x,y,w,h)
  local reserve=""
  for i=0,w*h-1 do
    reserve..=num2hex(mget(i%w,i\w))
  end
  printh(reserve,"@clip")
end

--convert mapdata to memory data
function num2hex(v)
  return sub(tostr(v,true),5,6)
end
__gfx__
000000000000000000000000088888800000000000000000000000000000000000aaaaa0000aaa000000a0000007707770077700000000000000000000000000
000000000888888008888880888888880888888008888800000000000888888000a000a0000a0a000000a0000777777677777770000000000000000000000000
000000008888888888888888888ffff888888888888888800888888088f1ff1800a909a0000a0a000000a0007766666667767777000000000000000000000000
00000000888ffff8888ffff888f1ff18888ffff88ffff8808888888888fffff8009aaa900009a9000000a0007677766676666677000000000000000000000000
0000000088f1ff1888f1ff1808fffff088f1ff1881ff1f80888ffff888fffff80000a0000000a0000000a0000000000000000000000000000000000000000000
0000000008fffff008fffff00033330008fffff00fffff8088fffff8083333800099a0000009a0000000a0000000000000000000000000000000000000000000
00000000003333000033330007000070073333000033337008f1ff10003333000009a0000000a0000000a0000000000000000000000000000000000000000000
000000000070070000700070000000000000070000007000077333700070070000aaa0000009a0000000a0000000000000000000000000000000000000000000
555555550000000000000000000000000000000000000000008888004999999449999994499909940300b0b06665666500000000000000000000000070000000
55555555000000000000000000000000000000000000000008888880911111199111411991140919003b33006765676500000000007700000770070007000007
550000550000000000000000000000000aaaaaa00000000008788880911111199111911949400419028888206770677000000000007770700777000000000000
55000055007000700499994000000000a998888a0000000008888880911111199494041900000044089888800700070000000000077777700770000000000000
55000055007000700050050000000000a988888a0000000008888880911111199114094994000000088889800700070000000000077777700000700000000000
55000055067706770005500000000000aaaaaaaa0000000008888880911111199111911991400499088988800000000000000000077777700000077000000000
55555555567656760050050000000000a980088a0000000000888800911111199114111991404119028888200000000000000000070777000007077007000070
55555555566656660005500004999940a988888a0000000000000000499999944999999444004994002882000000000000000000000000007000000000000000
5777777557777777777777777777777577cccccccccccccccccccc77577777755555555555555555555555555500000007777770000000000000000000000000
77777777777777777777777777777777777cccccccccccccccccc777777777775555555555555550055555556670000077777777000777770000000000000000
777c77777777ccccc777777ccccc7777777cccccccccccccccccc777777777775555555555555500005555556777700077777777007766700000000000000000
77cccc77777cccccccc77cccccccc7777777cccccccccccccccc7777777cc7775555555555555000000555556660000077773377076777000000000000000000
77cccc7777cccccccccccccccccccc777777cccccccccccccccc777777cccc775555555555550000000055555500000077773377077660000777770000000000
777cc77777cc77ccccccccccccc7cc77777cccccccccccccccccc77777cccc775555555555500000000005556670000073773337077770000777767007700000
7777777777cc77cccccccccccccccc77777cccccccccccccccccc77777c7cc77555555555500000000000055677770007333bb37070000000700007707777770
5777777577cccccccccccccccccccc7777cccccccccccccccccccc7777cccc77555555555000000000000005666000000333bb30000000000000000000077777
77cccc7777cccccccccccccccccccc77577777777777777777777775777ccc775555555550000000000000050000066603333330000000000000000000000000
777ccc7777cccccccccccccccccccc77777777777777777777777777777cc7775055555555000000000000550007777603b333300000000000ee0ee000000000
777ccc7777cc7cccccccccccc77ccc777777ccc7777777777ccc7777777cc77755550055555000000000055500000766033333300000000000eeeee000000030
77ccc77777ccccccccccccccc77ccc77777ccccc7c7777ccccccc77777ccc777555500555555000000005555000000550333b33000000000000e8e00000000b0
77ccc777777cccccccc77cccccccc777777ccccccc7777c7ccccc77777cccc7755555555555550000005555500000666003333000000b00000eeeee000000b30
777cc7777777ccccc777777ccccc77777777ccc7777777777ccc777777cccc775505555555555500005555550007777600044000000b000000ee3ee003000b00
777cc777777777777777777777777777777777777777777777777777777cc7775555555555555550055555550000076600044000030b00300000b00000b0b300
77cccc77577777777777777777777775577777777777777777777775577777755555555555555555555555550000005500999900030330300000b00000303300
5777755700000000077777777777777777777770077777700000000000000000cccccccc00000000000000000000000000000000000000000000000000000000
7777777700000000700007770000777000007777700077770000000000000000c77ccccc00000000000000000000000000000000000000000000000000000000
7777cc770000000070cc777cccc777ccccc7770770c777070000000000000000c77cc7cc00000000000000000000000000000000000000000000000000000000
777ccccc0000000070c777cccc777ccccc777c0770777c070000000000000000cccccccc00000000000000000000000000006000000000000000000000000000
77cccccc00000000707770000777000007770007777700070002eeeeeeee2000cccccccc00000000000000000000000000060600000000000000000000000000
57cc77cc0000000077770000777000007770000777700007002eeeeeeeeee200cc7ccccc00000000000000000000000000d00060000000000000000000000000
577c77cc000000007000000000000000000c000770000c0700eeeeeeeeeeee00ccccc7cc0000000000000000000000000d00000c000000000000000000000000
777ccccc000000007000000000000000000000077000000700e22222e2e22e00cccccccc000000000000000000000000d000000c000000000000000000000000
777ccccc000000007000000000000000000000077000000700eeeeeeeeeeee000000000000000000000000000000000c0000000c000600000000000000000000
577ccccc000000007000000c000000000000000770cc000700e22e2222e22e00000000000000000000000000000000d000000000c060d0000000000000000000
57cc7ccc0000000070000000000cc0000000000770cc000700eeeeeeeeeeee0000000000000000000000000000000c00000000000d000d000000000000000000
77cccccc0000000070c00000000cc00000000c0770000c0700eee222e22eee0000000000000000000000000000000c0000000000000000000000000000000000
777ccccc000000007000000000000000000000077000000700eeeeeeeeeeee005555555506666600666666006600c00066666600066666006666660066666600
7777cc770000000070000000000000000000000770c0000700eeeeeeeeeeee00555555556666666066666660660c000066666660666666606666666066666660
777777770000000070000000c0000000000000077000000700ee77eee7777e005555555566000660660000006600000066000000660000000066000066000000
57777577000000007000000000000000000000077000c007077777777777777055555555dd000000dddd0000dd000000dddd0000ddddddd000dd0000dddd0000
000000000000000070000000000000000000000770000007007777005000000000000005dd000dd0dd000000dd0000d0dd000000000000d000dd0000dd000000
00aaaaaa00000000700000000000000000000007700c0007070000705500000000000055ddddddd0dddddd00ddddddd0dddddd00ddddddd000dd0000dddddd00
0a99999900000000700000000000c00000000007700000077077000755500000000005550ddddd00ddddddd0ddddddd0ddddddd00ddddd0000dd0000ddddddd0
a99aaaaa000000007000000cc0000000000000077000cc077077bb07555500000000555500000000000000000000000000000000000000000000000000000000
a9aaaaaa000000007000000cc0000000000c00077000cc07700bbb07555555555555555566666066660006660600060000006666606666000600000666060006
a99999990000000070c00000000000000000000770c00007700bbb07555555555555555500600060000060000600060000000060006000006060006000060006
a9999999000000007000000000000000000000077000000707000070555555555555555500600060000600000600060000000060006000060006060000060006
a9999999000000000777777777777777777777700777777000777700555555555555555500d000dddd0d00000ddddd00000000d000dddd0600060d00000ddddd
aaaaaaaa0000000007777777777777777777777007777770004bbb00004b000000400bbb00d000d0000d00000d000d00000000d000d0000ddddd0d00000d000d
a49494a10000000070007770000077700000777770007777004bbbbb004bb000004bbbbb00d000d00000d0000d000d00000000d000d0000d000d00d0000d000d
a494a4a10000000070c777ccccc777ccccc7770770c7770704200bbb042bbbbb042bbb0000d000dddd000ddd0d000d00000000d000dddd0d000d000ddd0d000d
a49444aa0000000070777ccccc777ccccc777c0770777c07040000000400bbb004000000000001000000000000000000000000000000000000000000000c0000
a49999aa000000007777000007770000077700077777000704000000040000000400000000000100000000000000000000000000000000000000000000010000
a49444990000000077700000777000007770000777700c0742000000420000004200000000000100000000000000000000000000000000000000000000001000
a494a444000000007000000000000000000000077000000740000000400000004000000000000000000000000000000000000000000000000000000000000000
a4949999000000000777777777777777777777700777777040000000400000004000000000010000000000000000000000000000000000000000000000000010
00000000000000000000000000000000b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b12323232323232323232323232323232323232323232323232323232323232323
232323232323232323232323232323232323232323232352232352232352232352232362b2000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000540000000000000000000000000000000392a20392a20392a20392a203b2000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000011000000110000001100000011000000110000001100000011
00000000007200554363000000004353535353535332000393a30393a30393a30393a303b2000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000b3720000000072000000720000007200000072000000720000007200000072
000000000003005500000011110000000000000000030042535357535357535357535362b2000000000000000000000000000000000000000000000000000000
000000000000b34363b20000000000000000000000000000000000000000000000b3030000000003000000030000000300000003000000030000000300000003
00000000000300550000004363000000000000000003000392a20392a20392a20392a203b2000000000000000000000000000000000000000000000000000000
000000000000000000000000000000002100000000000000000000000000000000b3031111111103111111031111110311111103111111031111110311111103
11111111110300550000000000000000000000000003000393a30393a30393a30393a303b2000000001100000000000000000000000000000000000000000000
000000000000000000000000000000002253535353535363b20000000000000000b3425353535323535353235353532353535323535353235353532353535323
535353535362005500000000000000000000000000030042535357535357535357535362b20000001157b2000000000000000000000000000000000000000000
000000000000000000000000000000006200000000000000000000000000000000b3039200000000000000000011000011000000b1b1b1000000000000b1b100
00000000005400550000000000000000000000000003000392a20392a20392a20392a203b200001157b200000000000000000000000000000000000000000000
000000000000000000000000000000006200000000000000000000000000000000b3030000110000001100000072000072000000111111000000000000111100
00000000005500550000000000000000000000000003000393a30393a30393a30393a303b200b357b20000000000000000000000000000000000000000000000
000000000000000000000000000000006200000000000000001111111111111100b3730000720000007200000003000003000000122222222222222222222222
63b200000055005500000000000000000000000000030042535357535357535357535362b20000b1000000000000b34300000000000000000000000000000000
535353536300000000000043535353536200000000000000001222222222222200b3000000031111110311111103000003000000422434343434343434344733
b2000000005500550000435353630000000000000003000392a20392a20392a20392a203b200000000000000000000b100000000000000000000000000000000
000000000000000000000000000000006200000000000000004224343434445253535353532353535323535353522222522222225225353535353535354633b2
00000000005500550000000000000000000000000003000393a30393a30393a30393a303b2000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000062647400000000000042253535354552b1b1b1b1b100000000000000001323232323232352251515151515354633b200
000000000055005500000000000000000000000000030042535323535323535323535333b2000000000000000000000000000000000000000000000000000000
000000000000006474000000000000006265751000000000004225350035455200000000000000000000000000b1b1b1b1b1b100422515151515354633b20000
000000000055005500000000000000000000000000030003b2b1b1b1b1b1b1b1b1b1b1b100000000000000000000000000000000000000000000000000000000
001000000000006575000000000000005222223200000000004226363636465200000000000043535353535332111111111111004225151515354633b2000000
000000000055005500000000000000000000000000030003b2000000000000000000000000000000000000000000000000000000000000000000000000000000
22222222222222222222222222222222525252620000000000425252525252520000000000000000000000a2425353535353320042263636364633b200000000
000000000055005543630000000043532253535353330003b2000000000000000000000000000000004353535353535300000000000000000000000000000000
b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1000000000000000000000000000000001111110000000000000000000392000000a20300422323232333b20000000000
0000000000550055b1b1b1b1b1b1b1b10300000000000003b2000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000001222320000000000000000000300001100000300030000000000000000000000
000000000055005500000000000000000300435353535362b2000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000004254620000000000000000000300007200000300030000000000000000000000
00000000005500550000000000000000030000000000b303b2000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000004256620000000000000000000300000300000300030000000000000000000000
00000000005500550000000000000000030000000000b303b2000000000000000000000000000000000000111111111100000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000001323330000000000000000000300000300b37300422263b20000000000000000
00000000005500551222222232b20000030000000000b303b20000000000000000000000000000000000b3122222222200000000000000000000000000000000
210000000000000000000000000000000000000000000000000000000000000000000000000000111111111103000003000000001362b2000000000000000000
00000000005500554227374762b20000030000000000b303b20000000000000000000000000000000000b3422737475200000000000000000000000000000000
2253535353535363b2000000000000000000000000000000000000000000000000000000000000122222222262000003b20000001103b2000000000000000000
00000000274500551323232333b20000030000000000b303b20000000072b20000000000000000000000b3132323232300000000000000000000000000000000
620000000000000000000000000000000000000000000000000000000000000000000000000000422434344462000003b21111b31262b2000000000000000000
0000000000550055b2b1b1b1b1000000030000000000b303b20000000003b2000000000011000000000000b1b1b1b1b100000000000000000000000000000000
620000000000000000000000000000000000000000000000000000000000000000000000000000422535354562000013535322532333b2000000000000000000
0000000000550055b200000000000000030000000000b303b20000000003b200000000b357b20000000000000000000000000000000000000000000000000000
6200000000000000001111111111111100000000000000000000000000000000647400000000004225000045620000000000030000b100000000000000000000
0000000000550055b200000000000000030000000000b303b20017170073b20000000000b1000000000000000000000000000000000000000000000000000000
6200000000000000b312222222222222000000000000000000000000000000006575100000000042250000456200000011000300000000000000000000000000
00000000005500550000000000000000030000000000b303b200b37200b100000000000000000000000000000000000000000000000000000000000000000000
6200000000000000b342243434344452000000000000000000000000000000002222223200000042250000456200000072000300122222223200000000000000
00000000005500550000000000000000030000000000b303b200b303000000000000000000000000000000000000000000000000000000000000000000000000
6264740000000000b342253535354552000000000000000000000000000000005252526200000042250000456200000003000300422434446200000000000000
00000000005500550000000000000000030000000000b373b200b303000000000000000000000000000000000000000000000000000000000000000000000000
6265751000000000b342253500354552000000000000000000000000000000005252526200000042250000456200000003000300422500456200000000000000
0000000000550055001222222222320003000000000000000000b303000000000000000000000000000000000000000000000000000000000000000000000000
5222223200000000b342263636364652000000000000000000000000000000005252526200000042263636466200000003000300422636466200000000000000
000000000055005500422737374762004222222232b200000000b303000000000000000000000000000000000000000000000000000000000000000000000000
5252526200000000b342525252525252000000000000000000000000000000005252526200000042525252526200000003000300425252525222222222222222
222222222255005500425252525262004252525262b200000000b342222222222222222222222222222222222222222200000000000000000000000000000000
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000006000000000000006000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000060600000000000000000000000000000000000000000000000000000000600000
00000000000000000000000000000000000000000000000000000000000000d00060000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000d00000c000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000d000000c000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000c0000000c000600000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000d000000000c060d0000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000c00000000000d000d000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000006666600666666006600c00066666600066666006666660066666600000000000000000000000000000000000000
0000000000000000000000000000000000006666666066666660660c000066666660666666606666666066666660000000000000000000000000000000000000
00000000000000000000006000000000000066000660660000006600000066000000660000000066000066000000000000000000000000000000000000000000
000000000000000000000000000000000000dd000000dddd0000dd000000dddd0000ddddddd000dd0000dddd0000000000000000000000000000000000000060
000000000000000000000000000000000000dd000dd0dd000000dd0000d0dd000000000000d000dd0000dd000000000000000000000000000000000000000000
000000000000000000000000000000000000ddddddd0dddddd00ddddddd0dddddd00ddddddd000dd0000dddddd00000000000000000000000000000000000000
0000000000000000000000000000000000000ddddd00ddddddd0ddddddd0ddddddd00ddddd0000dd0000ddddddd0000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000066666066660006660600060000006666606666000600000666060006000000000000000000000000000000000000
00000000000000000000000000000000000000600060000060000600060000000060006000006060006000060006000000000000000000000000000000000000
00000000000000000000000000000000000000600060000600000600060000000060006000060006060000060006000000000000000000000000000000000000
00000000000000000000000000000000000000d000dddd0d00000ddddd00000000d000dddd0600060d00000ddddd000000000000000000000000000000000000
00000000000000000000000000000000000000d000d0000d00000d000d00000000d000d0000ddddd0d00000d000d000000000000000000000000000000000000
00000000000000000000000000000000000000d000d00000d0000d000d00007000d000d0000d000d00d0000d000d000000000000000000000000000000000000
00000000000000000000000000000000000000d000dddd000ddd0d000d00000000d000dddd0d000d000ddd0d000d000000000000000000000000000000000000
000000000000000000000000000000000000000001000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000
00000000000000000000000000000000000000000100000000000000000000000000000000000000000000010000000000000000000000000000000000000000
00000000000000000000000000000000000000000100000000000000000000000000000000000000000000001000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000010000000000000000000000000000000000000000000000000010000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000555550000500555550000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000005500055005005505055000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000005505055005005550555000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000005500055005005505055000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000555550050000555550000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000008880088088000000888080800000888088808880888088808880887000000000000000000000000000000000000
00000000000000000000000000000000000008880808080800000808080800000808080808080080008000800800000000000000000000000000000000000000
00000000000000000000000000000000000008080808080800000880088800000880088808880080008000800880000000000000000000000000000000000000
00000000000000000000000000000000000008080808080800000808000800000808080808000080008000800800000000000000000000000000000000000000
00000000000000000000000000000000000008080880088800000888088800000808080808000080088800800888000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000660000000000000000000000000070000000000000
00000000000000000000000000000000660666066600660666066606000000066606060666066006060066660006660066000000000000000000000000000000
00000000000000000000000000000006000606060006000060060606000000006006060606060606060600000000600606000000000000000000000000000000
00000000000000000000000000000006660666066006000060066606000000006006660666770606600666000000600606000000000000000000000000000000
00000000000000000000000000000000060600060006000060060606000000006006060606770606060006000000600606000000000000000000000000000000
00000000000066000000000000000006600600066600660666060606660000006006060606060606060660000000600660000000000000000000000000000000
00000000000066000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000055505000505055505500055055505550550005505050555055005550555055500000000055500550555055005550055000000000000000
00000000000000000050005000505005005050500050505000505050005050050050500050005000500000000050505000500050500500500000000000000000
00000000000000000055005000555005005050500055505500505050005050050050505550555005500000000055505000550050500500500000000000000000
00000000000000000050005000005005005050505050005000505050505050050050505000500000500500000050505000500050500500500005000000000000
00000000000000000050005550555055505050555050005550505055500550555050505550555055505000000050500550555055505550055050000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000500005505550550000000550550055505050000000000550505055505000500005505550555055005550555000005550550055000000555050505550000
00000500050505050505000005000505050005050000000005000505005005000500050005050050050505000505000005050505050500000050050505000000
00000500050505500505000005550505055005500000000005000555005005000500055505550050050505500550000005550505050500000050055505500000
00000500050505050505000000050505050005050050000005000505005005000500000505000050050505000505000005050505050500000050050505000000
00000555055005050555000005500505055505050500000000550505055505550555055005000555055505550505000005050505055500000050050505550000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000555055500550555000000550555000005550505055500000055055505000555005505550555000000550500055500550055055500550000000000
00000000000505050005000050000005050500000000500505050000000500050005000500050000500500000005000500050505000500005005000000000000
00000000000550055005550050000005050550000000500555055000000500055005000550055500500550000005000500055505550555005005000000000000
00000000000505050000050050000005050500000000500505050000000500050005000500000500500500000005000500050500050005005005000000000000
00000000000505055505500050000005500500000000500505055500000055055505550555055000500555000000550555050505500550055500550000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000550055500550055005505550550000000000550055500550055005505550550000000550055000505550550055505550550005500550000000000
00000000000505005005000500050505050505000000000505005005000500050505050505000005000500005005050505055500050505050005000000000000
00000000000505005005550500050505500505000000000505005005550500050505500505000005000500005005550505050600550505050005550000000000
00000000000505005000050500650505050505005000000505005000050500050505050505000005050505005000050505050500050505050000050000000000
00000000000555055505500055055005050555050000000555055505500055055005050555005005550555050000050555050505550505005505500000000000
00000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000660666066600660666066006660600000000660666066606660000066606060000000000000000000000000000000
00000000000000000000000000070000006060606006006000060060606060600000006000606066606000000060606060000000000000000000000000000000
00000000000000000000000000000000006060660006006000060060606660600000006000666760606600000066006660000000000000000000000000000000
00000000000000000000000000000000006060606006006060060060606060600000006060606060606000000060600060000000000000000000000000000000
00000000000000000000000000000000006600606066606660666060606060666000006660606060606660000066606660000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000055505550550055005050000055505050055055500550055055000000000000005500055055505000000055505550555055505050000000000000
00000000000055505050505050505050000005005050505050505000505050500000050000005050505050005000000050505000505050505050000000000000
00000000000050505550505050505550000005005550505055005550505050500000555000005050505055005000000055005500550055005550000000000000
00000000000050505050505050500050000005005050505050500050505050500000050000005050505050005000000050505000505050500050000000000000
00000000000050505050555055505550000005005050550050505500550050500000000000005650550055505550000055505550505050505550000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__gff__
0000000000000000000000000000000004020000000000000000000200000000030303030303030304040402020000000303030303030303040404020202020200001313131302020300000000000000000013131313020204000000000000000000131313130004040000000000000000001313131300000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
32323232323232323232323300000000003b24252525252525252525252525250000000000000000000000000000000000000000003b302b00000000003b24250000000000000000000000000000000025262b0000000000000000000000002432323225323232323226000000003b2400000000000000000000000000000000
00000000000000000000000000000000003b31323232252525252525252525250000000000000000000000000000000000000000003b302b00000000003b24250000000000000000000000000000000025262b0000000000000000000000002400000030000000000030000000003b2400000000000000000000000000000000
0000000000000000000000000000000011001b1b1b3b244243442542434344250000000000000000000000000000000000000000003b302b00000000003b24251b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b25262b000000000000000000000000243b270030000000000030000000003b2400000000000000000000000000000000
0000000000000011111111111121222223000000003b245253542552535354253535353600000000000000000000000000717100003b302b00000000003b24250000000000000000000000000000000025262b000000000000000000000000243b300030000000000030000000003b2400000000000000000000000000000000
0000000000000034353535353532323226000000003b24525354255253535425000000000000000000000000000000002222232b003b302b00000000003b24250000000000000000000000000000000025262b000000000000000000000000243b303b30000000110030000000003b2400000000000000000000000000000000
0000000000000000000000000000000026000000003b24525354255253535425000000000000000000000000000000002545262b003b302b00000000003b24250000000000000000000000000000000025262b000000000000000000000000243b303b3000003b270030000000003b2400000000000000000000000000000000
0000000000000000000000000000000026000000003b24626364256263636425000000000000000000000000000000002565262b003b372b00000000003b24250000000000000000000000000000000025262b000000111111111111111111243b303b3000003b300030000000003b2400000000000000000000000000000000
2222222223111111111111000000000025230000003b31323232252525252525000000000000000000000000000000003232332b00001b0000000000003b242500000000000000120000000000000000252600000000343535353535353535323b303b3000003b303b30000000003b2400000000000000000000000000000000
3232323232353535353536000000000025262b000000001b1b3b244243434425000000000000000000000000000034352b0000000000003b272b0000003b242535360000003435353535353535353500252600000000000000000000000000003b303b3000003b303b30000000003b2400000000000000000000000000000000
000000000000000000000000000000002526111111000000003b245200005425000000000000000000000000000000002b0000000000003b302b0000003b24251b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b252600000000000000000000000000003b303b3700003b303b30000000003b2400000000000000000000000000000000
000000000000000000000000000000002525222223000000003b245200005425000000000000000000000000000000002b0000000000003b302b003b2122252500000000000000000000000000000000252600000000000000000000000000003b30000000003b303b30000000003b2400000000000000000000000000000000
000000111111111111212222222222222542434426000000003b245200005425464700000000000000000000000000002b0000000000003b302b003b2442442500000000000000000000000000000000323300000000000000000000000000003b313535353535263b30000000003b2400000000000000000000000000000000
000000212222222222254243434344252552535426000000003b245200005425565700010000000000000000000000002b0000004647003b372b003b24525425000000000000000000000000000000000000000000000000000000000000000000000000000000303b30000000003b2400000000000000000000000000000000
004647244243434343435353535354252562636425230000003b246263636425353535360000000000000000000000002b000100565700001b00003b24525425000000000000464700000000000000000000000000464700000000000000000000004647000000303b37000000003b2400000000000000000000000000000000
015657246263636363636363636364252525252525262b00003b3132323225250000000000000000000000000000000022222222222223000000003b24626425010000120000565700000000000000000000010000565700000000000000000023005657000100300000000000003b2400000000000000000000000000000000
22222225252525252525252525252525257273737426111111001b1b1b3b24250000000000000000000000000000000025252525252526000000003b2425252522222222222222222222222222222222222222222222222222222222222222222522222222222225222222222222222500000000000000000000000000000000
32323232323232323232323232323300252525252525222223000000003b24253b2432323232323232323232323232323232323232253232323232323226002425252525252525252525252525260024254264252542642525426425330000002525252525252525252526000000000000000000000000000000000000000000
00000000001b1b1b1b00000000000000254243434343434426000000003b24253b3000000000000000000000001700000000000000244273737373734430002425424343434343434343434344260024736425254264252542642533000000002542434343434343434426000000000000000000000000000000000000000000
00212222231111111121222222222222255253535353535426000000003b24253b3000464700213535353535353600003b21222300245200000000005426002425525353535353535353535354260024252525426425254264253300000000002552535353535353535426000000000000000000000000000000000000000000
00244244252222222225424343434425255253000000535426000000003b24253b3000565700300000001100000000013b24452600245200000000005426002425520000000000000000005354260024252542642525426425330000000000002552534141414141535426000000000000000000000000000000000000000000
00245253434343434343535353535425256263636363636425230000003b24253b24353535353311003b2000000000343b24552600245200000000005426002425520000536363636363636364260024254264252542642533000000000000002552534141414141536426000016000000000000000000000000000000000000
00246263636363636363636363636425252525252525252525262b00003b31323b30000011003b2000000000000000003b245526002452000000000054260024255200005425323232323232322600247364252542642533000000000000000025525341414141536425332b0000000000000000000000000000000000000000
0031323232323232323232323232323225727373737373737426111111001b1b3b30003b2000000000000000000000113b2455260024520000000000542600242552000054260000000000000030002425252542642533000000000000000000256263636363636425332b000000000000000000000000000000000000000000
000000000000001b1b1b1b0000000000252525252525252525252222230000003b300000000000000000000011003b203b24552600245200000000005426002425520000542600000000000000300024252542642533000000004100000000003232323232323232332b00000000000000000000000000000000000000000000
22222222222223111111112122222300254243434343434343434344260000003b370000000000000011003b202b001b3b24552600245200000000005426002425626363642600000011000000300024254264253300000000000000000000000000000000717100000000000000000000000000000000000000000000000000
254243434344252222222225424426002552535353535353535353542600000000000000000011003b202b001b0000003b24552600245200000000005426002432323232322600000027000000300024436425330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
256263635353434343434343535426002552530000000000000053542600464700000011003b202b001b0000000000003b24552600246263636363636426002400000000003000000030000000300024642533000000000000000000000000004647000000000000000000000000000000000000000000000000000000000000
323232256263636363636363636426002562636363636363636363642601565700003b202b001b0000000000000000003b24652600243232323232323226002446470000003000000030000000300024253300000000000000000000000000005657000100000000000000000000000000000000000000000000000000000000
00000031323232323232323232323300252525252525252525252525252222220000001b0000000000000000000000003b31322600300000000000000030002456570100003000000030000000300024330000000000000000000000000000002222222223000000000000000000000000000000000000000000000000000000
46470000001b1b1b1b1b00000000000000000000000000000000000000000000000000000000000000000000000000004647003000300021222222230030002422222223003000000030000000300024000000000000464700000000000000002525252526000000000000000000000000000000000000000000000000000000
5657012123111111111121222222222200000000000000000000000000000000000000000000000000000000000000005657013000300024427344260030002425252526003000000030000000300024000000000000565700010000000000002525252526000000000000000000000000000000000000000000000000000000
2222222525222222222225252525252500000000000000000000000000000000111111111111111111111111111111112222222600300024552755260030002425252526003000000030000000300024222222222222222222222222222222222525252526000000000000000000000000000000000000000000000000000000
__sfx__
0002000036370234702f3701d4702a37017470273701347023370114701e3700e4701a3600c46016350084401233005420196001960019600196003f6003f6003f6003f6003f6003f6003f6003f6003f6003f600
0002000011070130701a0702407000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300000d07010070160702207000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200000642008420094200b420224402a4503c6503b6503b6503965036650326502d6502865024640216401d6401a64016630116300e6300b62007620056100361010600106000060000600006000060000600
000400000f0701e070120702207017070260701b0602c060210503105027040360402b0303a030300203e02035010000000000000000000000000000000000000000000000000000000000000000000000000000
000300000977009770097600975008740077300672005715357003470034700347003470034700347003570035700357003570035700347003470034700337003370033700337000070000700007000070000700
00030000241700e1702d1701617034170201603b160281503f1402f120281101d1101011003110001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
00020000101101211014110161101a120201202613032140321403410000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
00030000070700a0700e0701007016070220702f0702f0602c0602c0502f0502f0402c0402c0302f0202f0102c000000000000000000000000000000000000000000000000000000000000000000000000000000
0003000005110071303f6403f6403f6303f6203f6103f6153f6003f6003f600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600
011000200177500605017750170523655017750160500605017750060501705076052365500605017750060501775017050177500605236550177501605006050177500605256050160523655256050177523655
002000001d0401d0401d0301d020180401804018030180201b0301b02022040220461f0351f03016040160401d0401d0401d002130611803018030180021f061240502202016040130201d0401b0221804018040
00100000070700706007050110000707007060030510f0700a0700a0600a0500a0000a0700a0600505005040030700306003000030500c0700c0601105016070160600f071050500a07005050030510a0700a060
000400000c5501c5601057023570195702c5702157037570285703b5702c5703e560315503e540315303e530315203f520315203f520315103f510315103f510315103f510315103f50000500005000050000500
000400002f7402b760267701d7701577015770197701c750177300170015700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700
00030000096450e655066550a6550d6550565511655076550c655046550965511645086350d615006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605
011000001f37518375273752730027300243001d300263002a3001c30019300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300
011000002953429554295741d540225702256018570185701856018500185701856000500165701657216562275142753427554275741f5701f5601f500135201b55135530305602454029570295602257022560
011000200a0700a0500f0710f0500a0600a040110701105007000070001107011050070600704000000000000a0700a0500f0700f0500a0600a0401307113050000000000013070130500f0700f0500000000000
002000002204022030220201b0112404024030270501f0202b0402202027050220202904029030290201601022040220302b0401b030240422403227040180301d0401d0301f0521f0421f0301d0211d0401d030
0108002001770017753f6253b6003c6003b6003f6253160023650236553c600000003f62500000017750170001770017753f6003f6003f625000003f62500000236502365500000000003f625000000000000000
002000200a1400a1300a1201113011120111101b1401b13018152181421813213140131401313013120131100f1400f1300f12011130111201111016142161321315013140131301312013110131101311013100
001000202e750377502e730377302e720377202e71037710227502b750227302b7301d750247501d730247301f750277501f730277301f7202772029750307502973030730297203072029710307102971030710
000600001877035770357703576035750357403573035720357103570000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700
001800202945035710294403571029430377102942037710224503571022440274503c710274403c710274202e450357102e440357102e430377102e420377102e410244402b45035710294503c710294403c710
0018002005570055700557005570055700000005570075700a5700a5700a570000000a570000000a5700357005570055700557000000055700557005570000000a570075700c5700c5700f570000000a57007570
010c00103b6352e6003b625000003b61500000000003360033640336303362033610336103f6003f6150000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c002024450307102b4503071024440307002b44037700244203a7102b4203a71024410357102b410357101d45033710244503c7101d4403771024440337001d42035700244202e7101d4102e7102441037700
011800200c5700c5600c550000001157011560115500c5000c5700c5600f5710f56013570135600a5700a5600c5700c5600c550000000f5700f5600f550000000a5700a5600a5500f50011570115600a5700a560
001800200c5700c5600c55000000115701156011550000000c5700c5600f5710f56013570135600f5700f5600c5700c5700c5600c5600c5500c5300c5000c5000c5000a5000a5000a50011500115000a5000a500
000c0020247712477024762247523a0103a010187523a0103501035010187523501018750370003700037000227712277222762227001f7711f7721f762247002277122772227620070027771277722776200700
000c0020247712477024762247523a0103a010187503a01035010350101875035010187501870018700007001f7711f7701f7621f7521870000700187511b7002277122770227622275237012370123701237002
000c0000247712477024772247722476224752247422473224722247120070000700007000070000700007002e0002e0002e0102e010350103501033011330102b0102b0102b0102b00030010300123001230012
000c00200c3320c3320c3220c3220c3120c3120c3120c3020c3320c3320c3220c3220c3120c3120c3120c30207332073320732207322073120731207312073020a3320a3320a3220a3220a3120a3120a3120a302
000c00000c3300c3300c3200c3200c3100c3100c3103a0000c3300c3300c3200c3200c3100c3100c3103f0000a3300a3201333013320073300732007310113000a3300a3200a3103c0000f3300f3200f3103a000
00040000336251a605000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005
000c00000c3300c3300c3300c3200c3200c3200c3100c3100c3100c31000000000000000000000000000000000000000000000000000000000000000000000000a3000a3000a3000a3000a3310a3300332103320
001000000c3500c3400c3300c3200f3500f3400f3300f320183501834013350133401835013350163401d36022370223702236022350223402232013300133001830018300133001330016300163001d3001d300
000c0000242752b27530275242652b26530265242552b25530255242452b24530245242352b23530235242252b22530225242152b21530215242052b20530205242052b205302053a2052e205002050020500205
001000102f65501075010753f615010753f6152f65501075010753f615010753f6152f6553f615010753f61500005000050000500005000050000500005000050000500005000050000500005000050000500005
0010000016270162701f2711f2701f2701f270182711827013271132701d2711d270162711627016270162701b2711b2701b2701b270000001b200000001b2000000000000000000000000000000000000000000
00080020245753057524545305451b565275651f5752b5751f5452b5451f5352b5351f5252b5251f5152b5151b575275751b545275451b535275351d575295751d545295451d535295351f5752b5751f5452b545
002000200c2650c2650c2550c2550c2450c2450c2350a2310f2650f2650f2550f2550f2450f2450f2351623113265132651325513255132451324513235132351322507240162701326113250132420f2600f250
00100000072750726507255072450f2650f2550c2750c2650c2550c2450c2350c22507275072650725507245072750726507255072450c2650c25511275112651125511245132651325516275162651625516245
000800201f5702b5701f5402b54018550245501b570275701b540275401857024570185402454018530245301b570275701b540275401d530295301d520295201f5702b5701f5402b5401f5302b5301b55027550
00100020112751126511255112451326513255182751826518255182451d2651d2550f2651824513275162550f2750f2650f2550f2451126511255162751626516255162451b2651b255222751f2451826513235
00100010010752f655010753f6152f6553f615010753f615010753f6152f655010752f6553f615010753f61500005000050000500005000050000500005000050000500005000050000500005000050000500005
001000100107501075010753f6152f6553f6153f61501075010753f615010753f6152f6553f6152f6553f61500005000050000500005000050000500005000050000500005000050000500005000050000500005
002000002904029040290302b031290242b021290142b01133044300412e0442e03030044300302b0412b0302e0442e0402e030300312e024300212e024300212b0442e0412b0342e0212b0442b0402903129022
000800202451524515245252452524535245352454524545245552455524565245652457500505245750050524565005052456500505245550050524555005052454500505245350050524525005052451500505
000800201f5151f5151f5251f5251f5351f5351f5451f5451f5551f5551f5651f5651f575000051f575000051f565000051f565000051f555000051f555000051f545000051f535000051f525000051f51500005
000500000373005731077410c741137511b7612437030371275702e5712437030371275702e5712436030361275602e5612435030351275502e5512434030341275402e5412433030331275202e5212431030311
002000200c2750c2650c2550c2450c2350a2650a2550a2450f2750f2650f2550f2450f2350c2650c2550c2450c2750c2650c2550c2450c2350a2650a2550a2450f2750f2650f2550f2450f235112651125511245
002000001327513265132551324513235112651125511245162751626516255162451623513265132551324513275132651325513245132350f2650f2550f2450c25011231162650f24516272162520c2700c255
000300001f3302b33022530295301f3202b32022520295201f3102b31022510295101f3002b300225002950000000000000000000000000000000000000000000000000000000000000000000000000000000000
000b00002935500300293453037030360303551330524300243050030013305243002430500300003002430024305003000030000300003000030000300003000030000300003000030000300003000030000300
001000003c5753c5453c5353c5253c5153c51537555375453a5753a5553a5453a5353a5253a5253a5153a51535575355553554535545355353553535525355253551535515335753355533545335353352533515
00100000355753555535545355353552535525355153551537555375353357533555335453353533525335253a5753a5453a5353a5253a5153a51533575335553354533545335353353533525335253351533515
001000200c0600c0300c0500c0300c0500c0300c0100c0000c0600c0300c0500c0300c0500c0300c0100f0001106011030110501103011010110000a0600a0300a0500a0300a0500a0300a0500a0300a01000000
001000000506005030050500503005010050000706007030070500703007010000000f0600f0300f010000000c0600c0300c0500c0300c0500c0300c0500c0300c0500c0300c010000000c0600c0300c0100c000
0010000003625246150060503615246251b61522625036150060503615116253361522625006051d6250a61537625186152e6251d615006053761537625186152e6251d61511625036150060503615246251d615
00100020326103261032610326103161031610306102e6102a610256101b610136100f6100d6100c6100c6100c6100c6100c6100f610146101d610246102a6102e61030610316103361033610346103461034610
00400000302453020530235332252b23530205302253020530205302253020530205302153020530205302152b2452b2052b23527225292352b2052b2252b2052b2052b2252b2052b2052b2152b2052b2052b215
__music__
01 150a5644
00 0a160c44
00 0a160c44
00 0a0b0c44
00 14131244
00 0a160c44
00 0a160c44
02 0a111244
00 41424344
00 41424344
01 18191a44
00 18191a44
00 1c1b1a44
00 1d1b1a44
00 1f211a44
00 1f1a2144
00 1e1a2244
02 201a2444
00 41424344
00 41424344
01 2a272944
00 2a272944
00 2f2b2944
00 2f2b2c44
00 2f2b2944
00 2f2b2c44
00 2e2d3044
00 34312744
02 35322744
00 41424344
01 3d7e4344
00 3d7e4344
00 3d4a4344
02 3d3e4344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
01 383a3c44
02 393b3c44

