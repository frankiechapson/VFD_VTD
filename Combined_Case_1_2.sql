/***********************************************************************************************************/
/*

  1st + 2nd (combined) case.

  Here is an example how to handle historical logged predefined future changes

  This uses the functions and the package from Functions.sql file

*/

--------------------------------------------------------------------------------------------------
-- init
--------------------------------------------------------------------------------------------------

drop table CONSUMPTIONS_TM;
drop view  CONSUMPTIONS;
drop view  CONSUMPTION;


--------------------------------------------------------------------------------------------------
-- Consumption within a period
--------------------------------------------------------------------------------------------------

create table CONSUMPTIONS 
    (
      PERSON_ID         NUMBER         not null
    , VOLUME            NUMBER         not null   --  can change. estimated for future and fact for past
    , NOW_VFD           DATE           not null   --  beginning of data validitiy. historic log "from date"
    , NOW_VTD           DATE           not null   --  end of data validitiy. historic log "to date"
    , AT_VFD            DATE           not null   --  beginning of the consumption period 
    , AT_VTD            DATE           not null   --  end of the consumption period 
    );

create unique index IX1_CONSUMPTIONS on CONSUMPTIONS ( PERSON_ID, NOW_VFD, AT_VFD );

--------------------------------------------------------------------------------------------------
-- hide the complexity with views:
--------------------------------------------------------------------------------------------------

alter table CONSUMPTIONS rename to CONSUMPTIONS_TM;

-- in a certain time in past (or present) ("NOW")
create or replace view CONSUMPTIONS as         
select PERSON_ID
     , VOLUME
     , AT_VFD 
     , AT_VTD   
  from CONSUMPTIONS_TM 
 where TM_NOW between NOW_VFD and NOW_VTD;

-- from a certain time in past (or present, "NOW") what is valid at the "AT"
create or replace view CONSUMPTION as    
select PERSON_ID
     , VOLUME
     , AT_VFD 
     , AT_VTD   
  from CONSUMPTIONS_TM 
 where TM_NOW between NOW_VFD and NOW_VTD
   and TM_AT  between AT_VFD  and AT_VTD;


--------------------------------------------------------------------------------------------------
-- DELETE
--------------------------------------------------------------------------------------------------

create or replace trigger TR_CONSUMPTIONS_IDR 
  instead of delete on CONSUMPTIONS for each row
declare
    V_OLD_VFD         date;
    V_RIGHT_NOW       date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW and TM_AT = TM_RIGHT_NOW then       

        select max( NOW_VFD )
          into V_OLD_VFD
          from CONSUMPTIONS_TM
         where PERSON_ID = :old.PERSON_ID
           and AT_VFD    = :old.AT_VFD;

        if V_RIGHT_NOW - V_OLD_VFD <= TM_RESOL then

            -- If we are within the resolution, then it will be a real delete
            delete CONSUMPTIONS_TM 
             where PERSON_ID = :old.PERSON_ID
               and AT_VFD    = :old.AT_VFD
               and V_RIGHT_NOW between NOW_VFD and NOW_VTD;
            
        else

            -- in other cases it will be period close without a new one
            update CONSUMPTIONS_TM 
               set NOW_VTD   = V_RIGHT_NOW - TM_RESOL
             where PERSON_ID = :old.PERSON_ID
               and AT_VFD    = :old.AT_VFD
               and V_RIGHT_NOW between NOW_VFD and NOW_VTD;

        end if;

    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be deleted in real time (right now) only! Use TM_SET_NOW(null)!' );
    end if;
end;
/



--------------------------------------------------------------------------------------------------
-- INSERT we can insert into past as well, because it will be logged!
--------------------------------------------------------------------------------------------------

create or replace trigger TR_CONSUMPTIONS_IIR 
  instead of insert on CONSUMPTIONS for each row
declare
    V_CNT               number;
    V_CONSUMPTIONS_TM   CONSUMPTIONS_TM%rowtype;
    V_RIGHT_NOW         date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW and TM_AT = TM_RIGHT_NOW then       

        -- if there is not start date, then start from now
        V_CONSUMPTIONS_TM.AT_VFD := nvl( TM_TRUNC_DATE( :new.AT_VFD ), V_RIGHT_NOW );

        -- if there is not end, then never end
        V_CONSUMPTIONS_TM.AT_VTD := nvl( TM_TRUNC_DATE( :new.AT_VTD ), TM_LAST  );

        if V_CONSUMPTIONS_TM.AT_VTD >= V_CONSUMPTIONS_TM.AT_VFD then

            V_CONSUMPTIONS_TM.PERSON_ID := :new.PERSON_ID;
            V_CONSUMPTIONS_TM.VOLUME    := :new.VOLUME;
            V_CONSUMPTIONS_TM.NOW_VFD   := V_RIGHT_NOW;
            V_CONSUMPTIONS_TM.NOW_VTD   := TM_LAST;

            -- check overlaps!
            select count(*) 
              into V_CNT
              from CONSUMPTIONS
             where AT_VFD    <= V_CONSUMPTIONS_TM.AT_VTD
               and AT_VTD    >= V_CONSUMPTIONS_TM.AT_VFD
               and PERSON_ID  = V_CONSUMPTIONS_TM.PERSON_ID;

            if V_CNT = 0 then
                -- there is not overlappings, so we can insert it
                insert into CONSUMPTIONS_TM values V_CONSUMPTIONS_TM;
            else
                RAISE_APPLICATION_ERROR( -20002, 'Not allowed to insert data with overlapping periods!');
            end if;

        else
            RAISE_APPLICATION_ERROR( -20004, 'The start date must be less then the end date!' );
        end if;

    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be inserted in real time (right now) only! Use TM_SET_NOW(null)!');
    end if;
end;
/

--------------------------------------------------------------------------------------------------
-- UPDATE we can update the past as well, because it will be logged!
--------------------------------------------------------------------------------------------------

create or replace trigger TR_CONSUMPTIONS_IUR 
  instead of update on CONSUMPTIONS for each row
declare
    V_CNT               number;
    V_CONSUMPTIONS_TM   CONSUMPTIONS_TM%rowtype;
    V_OLD_VFD           date;
    V_RIGHT_NOW         date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW and TM_AT = TM_RIGHT_NOW then       

        V_CONSUMPTIONS_TM.PERSON_ID := :new.PERSON_ID;
        V_CONSUMPTIONS_TM.VOLUME    := :new.VOLUME;
        V_CONSUMPTIONS_TM.AT_VFD    := nvl( TM_TRUNC_DATE( :new.AT_VFD ), V_RIGHT_NOW );
        V_CONSUMPTIONS_TM.AT_VTD    := nvl( TM_TRUNC_DATE( :new.AT_VTD ), TM_LAST     );
        
        -- ...relevant data has changed?
        if PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.PERSON_ID , V_CONSUMPTIONS_TM.PERSON_ID ) 
        or PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.AT_VTD    , V_CONSUMPTIONS_TM.AT_VTD    ) 
        then
            
            -- check overlaps!
            select count(*) 
              into V_CNT
              from CONSUMPTIONS                                     /* ezt is NOW-ban nézzük */
             where AT_VFD       <= V_CONSUMPTIONS_TM.AT_VTD
               and AT_VTD       >= V_CONSUMPTIONS_TM.AT_VFD
               and AT_VFD       != :old.AT_VFD
               and AT_VTD       != :old.AT_VTD
               and PERSON_ID     = V_CONSUMPTIONS_TM.PERSON_ID;

            if V_CNT = 0 then

                select max( NOW_VFD )
                  into V_OLD_VFD
                  from CONSUMPTIONS_TM
                 where PERSON_ID = :old.PERSON_ID
                   and AT_VFD    = :old.AT_VFD;

                -- if we are within the resolution it will be a normal update, because we can not create a new time period 
                if V_RIGHT_NOW - V_OLD_VFD <= TM_RESOL then

                    update CONSUMPTIONS_TM 
                       set PERSON_ID = V_CONSUMPTIONS_TM.PERSON_ID
                         , VOLUME    = V_CONSUMPTIONS_TM.VOLUME
                     where PERSON_ID = :old.PERSON_ID
                       and AT_VFD    = :old.AT_VFD
                       and V_RIGHT_NOW between NOW_VFD and NOW_VTD;
                 
                else
                    -- otherwise we logging the change
                    -- close the current data
                    update CONSUMPTIONS_TM 
                       set NOW_VTD   = V_RIGHT_NOW - TM_RESOL
                     where PERSON_ID = :old.PERSON_ID
                       and AT_VFD    = :old.AT_VFD
                       and V_RIGHT_NOW between NOW_VFD and NOW_VTD;
                    -- and insert the new one
                    if sql%rowcount = 1 then
                        V_CONSUMPTIONS_TM.NOW_VFD   := V_RIGHT_NOW;
                        V_CONSUMPTIONS_TM.NOW_VTD   := TM_LAST;
                        insert into CONSUMPTIONS_TM values V_CONSUMPTIONS_TM;
                    end if;

                end if;

            else
                RAISE_APPLICATION_ERROR( -20002, 'Not allowed to update data with overlapping periods!');
            end if;

        else
            -- here we can handle not relevant data changes
            -- this will be a simple update without logging
            null;      
        end if;
  
    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be updated in real time (right now) only! Use TM_SET_NOW(null)!');
    end if;
end;
/


--------------------------------------------------------------------------------------------------
--   Some example
--------------------------------------------------------------------------------------------------


-- how the estimated consumption changed between 2017.08.06 and 2017.08.16 for 2017.11.20 - 2017.12.10 period

exec dbms_output.put_line(  To_Char(sysdate,'yyyy.mm.dd hh24:mi:ss')  );
declare
    V_CNT       number;
    V_VOL       number;
begin
    for L_NOW in 0..10 loop

        TM_SET_NOW( to_date('2017.08.06','yyyy.mm.dd') + L_NOW );

        for L_AT in  0..20 loop

            TM_SET_AT(  to_date('2017.11.20','yyyy.mm.dd') + L_AT );

            select count(*)
                 , sum( VOLUME )  
              into V_CNT 
                 , V_VOL
              from PERSONS
                 , CONSUMPTION 
             where PERSONS.ID = CONSUMPTION.PERSON_ID;

        end loop;

        dbms_output.put_line( 'Now : '||to_char( TM_NOW,'yyyy.mm.dd')||' Cnt : '||to_char( V_CNT )||' Vol : '||to_char( V_VOL ) );

    end loop;

end;
/
exec dbms_output.put_line(  To_Char(sysdate,'yyyy.mm.dd hh24:mi:ss')  );


--------------------------------------------------------------------------------------------------
--  with ruler. It uses objects from Rulers.sql
--------------------------------------------------------------------------------------------------

select T_NOW.RULER_DATE   as "Now"
     , T_AT.RULER_DATE    as "At"
     , count(*)           as "Cnt"
     , sum(VOLUME)        as "Vol"
  from TM_RULER_D     T_NOW
     , TM_RULER_D     T_AT
     , PERSONS_TM
     , CONSUMPTIONS_TM      
 where PERSONS_TM.ID = CONSUMPTIONS_TM.PERSON_ID
   and T_NOW.RULER_DATE between PERSONS_TM.NOW_VFD                     and PERSONS_TM.NOW_VTD
   and T_NOW.RULER_DATE between CONSUMPTIONS_TM.NOW_VFD                and CONSUMPTIONS_TM.NOW_VTD
   and T_AT.RULER_DATE  between CONSUMPTIONS_TM.AT_VFD                 and CONSUMPTIONS_TM.AT_VTD
   and T_NOW.RULER_DATE between to_date('2017.08.06','yyyy.mm.dd') and to_date('2017.08.06','yyyy.mm.dd') + 10
   and T_AT.RULER_DATE  between to_date('2017.11.20','yyyy.mm.dd') and to_date('2017.11.20','yyyy.mm.dd') + 20
group by T_NOW.RULER_DATE
       , T_AT.RULER_DATE 
order by T_NOW.RULER_DATE
       , T_AT.RULER_DATE 
;

--------------------------------------------------------------------------------------------------
--  make it simplier 
--------------------------------------------------------------------------------------------------

create or replace view TEST_VW as 
select /*+ PARALLEL(8) */  
       T_NOW.RULER_DATE as "Now"
     , T_AT.RULER_DATE  as "At"
     , count(*)         as "Cnt"
     , sum(VOLUME)      as "Vol"
  from TM_RULER_D       T_NOW
     , TM_RULER_D       T_AT
     , PERSONS_TM
     , CONSUMPTIONS_TM      
 where PERSONS_TM.ID = CONSUMPTIONS_TM.PERSON_ID
   and T_NOW.RULER_DATE between PERSONS_TM.NOW_VFD         and PERSONS_TM.NOW_VTD
   and T_NOW.RULER_DATE between CONSUMPTIONS_TM.NOW_VFD    and CONSUMPTIONS_TM.NOW_VTD
   and T_AT.RULER_DATE  between CONSUMPTIONS_TM.AT_VFD     and CONSUMPTIONS_TM.AT_VTD
group by T_NOW.RULER_DATE
       , T_AT.RULER_DATE 
;


select * 
  from TEST_VW 
 where "Now" between to_date('2017.08.06','yyyy.mm.dd') and to_date('2017.08.06','yyyy.mm.dd') + 10
   and "At"  between to_date('2017.11.20','yyyy.mm.dd') and to_date('2017.11.20','yyyy.mm.dd') + 20
;

--------------------------------------------------------------------------------------------------
--  for a fix now with view
--------------------------------------------------------------------------------------------------

create or replace view TEST_2_VW as 
select /*+ PARALLEL(8) */  
       T_AT.RULER_DATE   as "At"
     , count(*)          as "Cnt"
     , sum(VOLUME)       as "Vol"
  from TM_RULER_D       T_AT
     , PERSONS
     , CONSUMPTIONS
 where PERSONS.ID = CONSUMPTIONS.PERSON_ID
   and T_AT.RULER_DATE  between CONSUMPTIONS.AT_VFD  and CONSUMPTIONS.AT_VTD
group by T_AT.RULER_DATE 
;

exec TM_SET_NOW( to_date('2017.08.06','yyyy.mm.dd') );

select * 
  from TEST_2_VW 
 where "At"  between to_date('2017.11.20','yyyy.mm.dd') and to_date('2017.11.20','yyyy.mm.dd') + 20
order by 1
;

exec TM_SET_NOW( to_date('2017.08.07','yyyy.mm.dd') );

select * 
  from TEST_2_VW 
 where "At"  between to_date('2017.11.20','yyyy.mm.dd') and to_date('2017.11.20','yyyy.mm.dd') + 20
order by 1
;

...

/***********************************************************************************************************/







