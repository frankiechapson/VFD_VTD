 
/*

    Example for managing times series (max quarter hourly resolution)

*/

--------------------------------------------------------------------------------------------------
-- init
drop table PRICES_TM;
drop view  PRICES;
drop view  PRICE;

--------------------------------------------------------------------------------------------------
-- this is a simple combined table ( logged predefined future/present changes ) and not time series
--------------------------------------------------------------------------------------------------

create table PRICES 
    (
      PRICE             NUMBER         not null   -- can change
    , NOW_VFD           DATE           not null    
    , NOW_VTD           DATE           not null    
    , AT_VFD            DATE           not null    
    , AT_VTD            DATE           not null    
    );

create unique index IX1_PRICES on PRICES ( NOW_VFD, AT_VFD );

--------------------------------------------------------------------------------------------------
-- Hide a the complexity with views
--------------------------------------------------------------------------------------------------

alter table PRICES rename to PRICES_TM;


create or replace view PRICES as 
select PRICE
     , AT_VFD 
     , AT_VTD   
  from PRICES_TM 
 where TM_NOW between NOW_VFD and NOW_VTD;


create or replace view PRICE as 
select PRICE
     , AT_VFD 
     , AT_VTD   
  from PRICES_TM 
 where TM_NOW between NOW_VFD and NOW_VTD
   and TM_AT  between AT_VFD  and AT_VTD;

--------------------------------------------------------------------------------------------------
-- DELETE
--------------------------------------------------------------------------------------------------

create or replace trigger TR_PRICES_IDR 
  instead of delete on PRICES for each row
declare
    V_OLD_VFD         date;
    V_RIGHT_NOW       date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW and TM_AT = TM_RIGHT_NOW then       

        select max( NOW_VFD )
          into V_OLD_VFD
          from PRICES_TM
         where AT_VFD    = :old.AT_VFD;

        -- If we are within the resolution, then it will be a real delete
        if V_RIGHT_NOW - V_OLD_VFD <= TM_RESOL then

            delete PRICES_TM 
             where AT_VFD    = :old.AT_VFD
               and V_RIGHT_NOW between NOW_VFD and NOW_VTD;
            
        else

            -- otherwise it will be period close without a new one
            update PRICES_TM 
               set NOW_VTD = V_RIGHT_NOW - TM_RESOL
             where AT_VFD  = :old.AT_VFD
               and V_RIGHT_NOW between NOW_VFD and NOW_VTD;

        end if;

    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be deleted in real time (right now) only! Use TM_SET_NOW(null)!' );
    end if;
end;
/

--------------------------------------------------------------------------------------------------
-- INSERT
--------------------------------------------------------------------------------------------------

create or replace trigger TR_PRICES_IIR 
  instead of insert on PRICES for each row
declare
    V_CNT               number;
    V_PRICES_TM         PRICES_TM%rowtype;
    V_RIGHT_NOW         date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW and TM_AT = TM_RIGHT_NOW then       

        -- if there is not start date, then start from now
        V_PRICES_TM.AT_VFD := nvl( TM_TRUNC_DATE( :new.AT_VFD ), V_RIGHT_NOW );

        -- if there is not end, then never end
        V_PRICES_TM.AT_VTD := nvl( TM_TRUNC_DATE( :new.AT_VTD ), TM_LAST  );

        if V_PRICES_TM.AT_VTD >= V_PRICES_TM.AT_VFD then

            V_PRICES_TM.PRICE    := :new.PRICE;
            V_PRICES_TM.NOW_VFD  := V_RIGHT_NOW;
            V_PRICES_TM.NOW_VTD  := TM_LAST;

            -- check overlaps!
            select count(*) 
              into V_CNT
              from PRICES
             where AT_VFD <= V_PRICES_TM.AT_VTD
               and AT_VTD >= V_PRICES_TM.AT_VFD;

            if V_CNT = 0 then
                -- there is not overlappings, so we can insert it
                insert into PRICES_TM values V_PRICES_TM;
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
-- UPDATE
--------------------------------------------------------------------------------------------------

create or replace trigger TR_PRICES_IUR 
  instead of update on PRICES for each row
declare
    V_CNT               number;
    V_PRICES_TM         PRICES_TM%rowtype;
    V_OLD_VFD           date;
    V_RIGHT_NOW         date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW and TM_AT = TM_RIGHT_NOW then       

        V_PRICES_TM.PRICE   := :new.PRICE;
        V_PRICES_TM.AT_VFD  := nvl( TM_TRUNC_DATE( :new.AT_VFD ), V_RIGHT_NOW );
        V_PRICES_TM.AT_VTD  := nvl( TM_TRUNC_DATE( :new.AT_VTD ), TM_LAST      );
           
        -- ...relevant data has changed?
        if PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.PRICE , V_PRICES_TM.PRICE  ) 
        or PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.AT_VTD, V_PRICES_TM.AT_VTD ) 
        then

            -- check overlaps!
            select count(*) 
              into V_CNT
              from PRICES
             where AT_VFD <= V_PRICES_TM.AT_VTD
               and AT_VTD >= V_PRICES_TM.AT_VFD
               and AT_VFD != :old.AT_VFD
               and AT_VTD != :old.AT_VTD;

            if V_CNT = 0 then

                select max( NOW_VFD )
                  into V_OLD_VFD
                  from PRICES_TM
                 where AT_VFD    = :old.AT_VFD;

                -- if we are within the resolution it will be a normal update, because we can not create a new time period 
                if V_RIGHT_NOW - V_OLD_VFD <= TM_RESOL then
                   
                    update PRICES_TM 
                       set PRICE   = V_PRICES_TM.PRICE
                         , AT_VTD  = V_PRICES_TM.AT_VTD
                     where AT_VFD  = :old.AT_VFD
                       and V_RIGHT_NOW between NOW_VFD and NOW_VTD;
                   
                else

                    -- otherwise we logging the change
                    -- close the current data                   
                    update PRICES_TM 
                       set NOW_VTD = V_RIGHT_NOW - TM_RESOL
                     where AT_VFD  = :old.AT_VFD
                       and V_RIGHT_NOW between NOW_VFD and NOW_VTD;
                    -- and insert the new one
                    if sql%rowcount = 1 then
                        V_PRICES_TM.NOW_VFD := V_RIGHT_NOW;
                        V_PRICES_TM.NOW_VTD := TM_LAST;
                        insert into PRICES_TM values V_PRICES_TM;
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

-- change the resolution to second, because we will use quarter hourly consumption data

create or replace function TM_RESOL ( I_DATE in date := sysdate ) return number deterministic is  
-- the resolution in day. Two date are identical within the resolution (period)
begin
    return 1/86400;                             -- second
--  return 1/1440;                              -- minute
--  return 1/24;                                -- hour
--  return 1;                                   -- day
--  return last_day( I_DATE );                  -- month
--  return add_months( trunc( I_DATE, 'YYYY' ), 12 ) - trunc( I_DATE, 'YYYY' );                  -- year
end;
/

exec TM_SET_NOW;
exec TM_SET_AT;

insert into PRICES ( PRICE, AT_VFD, AT_VTD ) values (  94, sysdate - 10           , sysdate - TM_RESOL );
insert into PRICES ( PRICE, AT_VFD, AT_VTD ) values ( 100, sysdate                , sysdate + 23 );
insert into PRICES ( PRICE, AT_VFD, AT_VTD ) values ( 110, sysdate + 23 + TM_RESOL, sysdate + 88 );
insert into PRICES ( PRICE, AT_VFD, AT_VTD ) values ( 111, sysdate + 88 + TM_RESOL, sysdate + 99 );
commit;


--------------------------------------------------------------------------------------------------
-- we can use different ways to calculate a daily/monthly/yearly price from different prices within day, month etc.
-- or we can use momentary like this:
--------------------------------------------------------------------------------------------------

create or replace view PRICES_QH_VW as
select TM_RULER_QH.RULER_DATE
     , PRICES.PRICE
  from TM_RULER_QH
     , PRICES
 where TM_RULER_QH.RULER_DATE between PRICES.AT_VFD and PRICES.AT_VTD
;

create or replace view PRICES_H_VW as
select TM_RULER_H.RULER_DATE
     , PRICES.PRICE
  from TM_RULER_H
     , PRICES
 where TM_RULER_H.RULER_DATE between PRICES.AT_VFD and PRICES.AT_VTD
/* alternativly example
select trunc( RULER_DATE, 'HH24') as RULER_DATE
     , avg( PRICE )               as PRICE   -- or min / max
  from PRICES_QH_VW
 group by trunc( RULER_DATE, 'HH24')
*/
;

create or replace view PRICES_D_VW as
select TM_RULER_D.RULER_DATE
     , PRICES.PRICE
  from TM_RULER_D
     , PRICES
 where TM_RULER_D.RULER_DATE between PRICES.AT_VFD and PRICES.AT_VTD
/* alternativly example
select trunc( RULER_DATE, 'DD') as RULER_DATE
     , avg( PRICE )             as PRICE        -- or min / max
  from PRICES_QH_VW                             -- or PRICES_H_VW
 group by trunc( RULER_DATE, 'DD')
*/
;

create or replace view PRICES_M_VW as
select TM_RULER_M.RULER_DATE
     , PRICES.PRICE
  from TM_RULER_M
     , PRICES
 where TM_RULER_M.RULER_DATE between PRICES.AT_VFD and PRICES.AT_VTD
/* alternativly example
select trunc( RULER_DATE, 'MM') as RULER_DATE    
     , avg( PRICE )             as PRICE        -- or min / max
  from PRICES_QH_VW                             -- or PRICES_H_VW or PRICES_D_VW
 group by trunc( RULER_DATE, 'MM')
*/
;





--------------------------------------------------------------------------------------------------
-- And here is a real time series, (special) combined table
--------------------------------------------------------------------------------------------------

drop table CONSUMPTIONS_TS_TM;
drop view  CONSUMPTIONS_TS;
drop view  CONSUMPTION_TS;


create table CONSUMPTIONS_TS
    (
      PERSON_ID        NUMBER         not null
    , VOLUME           NUMBER         not null   
    , NOW_VFD          DATE           not null    
    , NOW_VTD          DATE           not null    
    , AT_VTD           DATE           not null       -- in past (<=sysdate) that is a fact in future ( >sysdate) that is just an estimated value
    , LEN              NUMBER         not null       -- instead of AT_VFD here is the length in "QH"
    );

create unique index IX1_CONSUMPTIONS_TS on CONSUMPTIONS_TS ( PERSON_ID, NOW_VFD, AT_VTD );
create        index IX2_CONSUMPTIONS_TS on CONSUMPTIONS_TS ( NOW_VFD, AT_VTD, LEN );
create        index IX3_CONSUMPTIONS_TS on CONSUMPTIONS_TS ( AT_VTD, LEN );
create        index IX4_CONSUMPTIONS_TS on CONSUMPTIONS_TS ( LEN );


--------------------------------------------------------------------------------------------------
--  views instead of table
--------------------------------------------------------------------------------------------------
alter table CONSUMPTIONS_TS rename to CONSUMPTIONS_TS_TM;


create or replace view CONSUMPTIONS_TS as 
select PERSON_ID
     , VOLUME
     , AT_VTD 
     , LEN   
  from CONSUMPTIONS_TS_TM 
 where TM_NOW between NOW_VFD and NOW_VTD;


create or replace view CONSUMPTION_TS as 
select PERSON_ID
     , VOLUME
     , AT_VTD 
     , LEN   
  from CONSUMPTIONS_TS_TM 
 where TM_NOW between NOW_VFD and NOW_VTD
   and TM_AT  <  AT_VTD  
   and TM_AT  >= AT_VTD - ( LEN / 96 );  -- there is 96 QH in a day


-- .... and the triggers as usually:
--------------------------------------------------------------------------------------------------
-- DELETE
--------------------------------------------------------------------------------------------------

create or replace trigger TR_CONSUMPTIONS_TS_IDR 
  instead of delete on CONSUMPTIONS_TS for each row
declare
    V_OLD_VFD         date;
    V_RIGHT_NOW       date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW and TM_AT = TM_RIGHT_NOW then       

        select max( NOW_VFD )
          into V_OLD_VFD
          from CONSUMPTIONS_TS_TM
         where PERSON_ID = :old.PERSON_ID
           and AT_VTD    = :old.AT_VTD;

        if V_RIGHT_NOW - V_OLD_VFD <= TM_RESOL then

            delete CONSUMPTIONS_TS_TM 
             where PERSON_ID = :old.PERSON_ID
               and AT_VTD    = :old.AT_VTD
               and V_RIGHT_NOW between NOW_VFD and NOW_VTD;
            
        else

            update CONSUMPTIONS_TS_TM 
               set NOW_VTD    = V_RIGHT_NOW - TM_RESOL
             where PERSON_ID  = :old.PERSON_ID
               and AT_VTD     = :old.AT_VTD
               and V_RIGHT_NOW between NOW_VFD and NOW_VTD;

        end if;
    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be deleted in real time (right now) only! Use TM_SET_NOW(null)!' );
    end if;
end;
/

--------------------------------------------------------------------------------------------------
-- INSERT
--------------------------------------------------------------------------------------------------

create or replace trigger TR_CONSUMPTIONS_TS_IIR 
  instead of insert on CONSUMPTIONS_TS for each row
declare
    V_CNT                   number;
    V_CONSUMPTIONS_TS_TM    CONSUMPTIONS_TS_TM%rowtype;
    V_RIGHT_NOW             date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW and TM_AT = TM_RIGHT_NOW then       

        V_CONSUMPTIONS_TS_TM.AT_VTD    := :new.AT_VTD;
        V_CONSUMPTIONS_TS_TM.PERSON_ID := :new.PERSON_ID;
        V_CONSUMPTIONS_TS_TM.VOLUME    := :new.VOLUME;
        V_CONSUMPTIONS_TS_TM.NOW_VFD   := V_RIGHT_NOW;
        V_CONSUMPTIONS_TS_TM.NOW_VTD   := TM_LAST;
        V_CONSUMPTIONS_TS_TM.LEN       := :new.LEN;

        -- the following LEN values are allowed only
        if V_CONSUMPTIONS_TS_TM.LEN in ( 1, 4, 96, 2688, 2784, 2880, 2976, 35040, 35136 ) then

            -- ...and it can not start anytime
            if ( V_CONSUMPTIONS_TS_TM.LEN =  1 and to_char( V_CONSUMPTIONS_TS_TM.AT_VTD, 'MI'     ) in ('00','15','30','45') )
            or ( V_CONSUMPTIONS_TS_TM.LEN =  4 and to_char( V_CONSUMPTIONS_TS_TM.AT_VTD, 'MI'     ) = '00'   )
            or ( V_CONSUMPTIONS_TS_TM.LEN = 96 and to_char( V_CONSUMPTIONS_TS_TM.AT_VTD, 'HH24MI' ) = '0000' ) 
            or ( V_CONSUMPTIONS_TS_TM.LEN in ( 2688, 2784, 2880, 2976 ) and to_char( V_CONSUMPTIONS_TS_TM.AT_VTD, 'DDHH24MI'   ) = '010000'   ) 
            or ( V_CONSUMPTIONS_TS_TM.LEN in ( 35040, 35136           ) and to_char( V_CONSUMPTIONS_TS_TM.AT_VTD, 'MMDDHH24MI' ) = '01010000' ) then

                -- check overlaps!
                select count(*) 
                  into V_CNT
                  from CONSUMPTIONS_TS
                 where PERSON_ID              = V_CONSUMPTIONS_TS_TM.PERSON_ID
                   and AT_VTD                 > V_CONSUMPTIONS_TS_TM.AT_VTD - ( V_CONSUMPTIONS_TS_TM.LEN / 96 )
                   and AT_VTD - ( LEN / 96 )  < V_CONSUMPTIONS_TS_TM.AT_VTD;
                    
                if V_CNT = 0 then
                    insert into CONSUMPTIONS_TS_TM values V_CONSUMPTIONS_TS_TM;
                else
                    RAISE_APPLICATION_ERROR( -20002, 'Not allowed to update data with overlapping periods!');
                end if;

            else
                RAISE_APPLICATION_ERROR( -20005, 'That is not a valid AT_VTD value!' );
            end if;

        else
            RAISE_APPLICATION_ERROR( -20004, 'That is not a valid LEN value!' );
        end if;

    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be inserted in real time (right now) only! Use TM_SET_NOW(null)!');
    end if;
end;
/

--------------------------------------------------------------------------------------------------
-- UPDATE
--------------------------------------------------------------------------------------------------

create or replace trigger TR_CONSUMPTIONS_TS_IUR 
  instead of update on CONSUMPTIONS_TS for each row
declare
    V_CNT                   number;
    V_CONSUMPTIONS_TS_TM    CONSUMPTIONS_TS_TM%rowtype;
    V_OLD_VFD               date;
    V_RIGHT_NOW             date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW and TM_AT = TM_RIGHT_NOW then       

        V_CONSUMPTIONS_TS_TM.AT_VTD    := :new.AT_VTD;
        V_CONSUMPTIONS_TS_TM.LEN       := :new.LEN;
        V_CONSUMPTIONS_TS_TM.VOLUME    := :new.VOLUME;
        V_CONSUMPTIONS_TS_TM.PERSON_ID := :new.PERSON_ID;

        if V_CONSUMPTIONS_TS_TM.LEN in ( 1, 4, 96, 2688, 2784, 2880, 2976, 35040, 35136 ) then
        
            if ( V_CONSUMPTIONS_TS_TM.LEN =  1 and to_char( V_CONSUMPTIONS_TS_TM.AT_VTD, 'MI'     ) in ('00','15','30','45') )
            or ( V_CONSUMPTIONS_TS_TM.LEN =  4 and to_char( V_CONSUMPTIONS_TS_TM.AT_VTD, 'MI'     ) = '00'   )
            or ( V_CONSUMPTIONS_TS_TM.LEN = 96 and to_char( V_CONSUMPTIONS_TS_TM.AT_VTD, 'HH24MI' ) = '0000' ) 
            or ( V_CONSUMPTIONS_TS_TM.LEN in ( 2688, 2784, 2880, 2976 ) and to_char( V_CONSUMPTIONS_TS_TM.AT_VTD, 'DDHH24MI'   ) = '010000'   ) 
            or ( V_CONSUMPTIONS_TS_TM.LEN in ( 35040, 35136           ) and to_char( V_CONSUMPTIONS_TS_TM.AT_VTD, 'MMDDHH24MI' ) = '01010000' ) then
        
                if PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.PERSON_ID, V_CONSUMPTIONS_TS_TM.PERSON_ID ) 
                or PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.VOLUME   , V_CONSUMPTIONS_TS_TM.VOLUME    )  
                or PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.LEN      , V_CONSUMPTIONS_TS_TM.LEN       ) 
                then
                
                    select count(*) 
                      into V_CNT
                      from CONSUMPTIONS_TS                        
                     where PERSON_ID              = V_CONSUMPTIONS_TS_TM.PERSON_ID
                       and AT_VTD                 > V_CONSUMPTIONS_TS_TM.AT_VTD - ( V_CONSUMPTIONS_TS_TM.LEN / 96 )
                       and AT_VTD - ( LEN / 96 )  < V_CONSUMPTIONS_TS_TM.AT_VTD
                       and AT_VTD                != :old.AT_VTD
                       and LEN                   != :old.LEN;
                
                    if V_CNT = 0 then
        
                        select max( NOW_VFD )
                          into V_OLD_VFD
                          from CONSUMPTIONS_TS_TM  
                         where PERSON_ID = :old.PERSON_ID
                           and AT_VTD    = :old.AT_VTD;
                
                        if V_RIGHT_NOW - V_OLD_VFD <= TM_RESOL then
                        
                            update CONSUMPTIONS_TS_TM 
                               set PERSON_ID  = V_CONSUMPTIONS_TS_TM.PERSON_ID
                                 , VOLUME     = V_CONSUMPTIONS_TS_TM.VOLUME
                                 , LEN        = V_CONSUMPTIONS_TS_TM.LEN
                             where PERSON_ID  = :old.PERSON_ID
                               and AT_VTD     = :old.AT_VTD
                               and V_RIGHT_NOW between NOW_VFD and NOW_VTD;
                        
                        else
                
                            update CONSUMPTIONS_TS_TM 
                               set NOW_VTD    = V_RIGHT_NOW - TM_RESOL
                             where PERSON_ID  = :old.PERSON_ID
                               and AT_VTD     = :old.AT_VTD
                               and V_RIGHT_NOW between NOW_VFD and NOW_VTD;
                        
                            if sql%rowcount = 1 then
                                V_CONSUMPTIONS_TS_TM.NOW_VFD := V_RIGHT_NOW;
                                V_CONSUMPTIONS_TS_TM.NOW_VTD := TM_LAST;
                                insert into CONSUMPTIONS_TS_TM values V_CONSUMPTIONS_TS_TM;
                            end if;
                        
                        end if;
                
                    else
                        RAISE_APPLICATION_ERROR( -20002, 'Not allowed to update data with overlapping periods!');
                    end if;
                
                end if;
        
            else
                RAISE_APPLICATION_ERROR( -20005, 'That is not a valid AT_VTD value!' );
            end if;
        
        else
            RAISE_APPLICATION_ERROR( -20004, 'That is not a valid LEN value!' );
        end if;

    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be updated in real time (right now) only! Use TM_SET_NOW(null)!');
    end if;
end;
/


--------------------------------------------------------------------------------------------------
--   generate some data QH, H and D data
--------------------------------------------------------------------------------------------------

exec TM_SET_AT;
exec TM_SET_NOW;

declare
    V_CONSUMPTIONS_TS      CONSUMPTIONS_TS%rowtype;
    V_RESOL                number;
begin
    -- for 10 persons

    for L_ID in 1..10  
    loop

        V_CONSUMPTIONS_TS.PERSON_ID := L_ID;

        -- for 100 days
        for L_D in 1..100 
        loop

            V_CONSUMPTIONS_TS.LEN    := round( dbms_random.value( 1, 3 ) );
            V_CONSUMPTIONS_TS.AT_VTD := trunc(sysdate) + L_D;

            if V_CONSUMPTIONS_TS.LEN = 2 then  

                V_CONSUMPTIONS_TS.LEN    := 4;    -- H
                --we need 24 H row
                for L_I in 1..24
                loop
                    V_CONSUMPTIONS_TS.VOLUME  := round( dbms_random.value( 100, 10000 ) );
                    insert into CONSUMPTIONS_TS values V_CONSUMPTIONS_TS;
                    V_CONSUMPTIONS_TS.AT_VTD  := V_CONSUMPTIONS_TS.AT_VTD - ( V_CONSUMPTIONS_TS.LEN / 96 );
                end loop;

            elsif V_CONSUMPTIONS_TS.LEN = 3 then

                V_CONSUMPTIONS_TS.LEN := 96;   -- D
                --we need 1 D row
                 V_CONSUMPTIONS_TS.VOLUME  := round( dbms_random.value( 100, 10000 ) );
                 insert into CONSUMPTIONS_TS values V_CONSUMPTIONS_TS;

            else                               -- QH

                --we need 96 QH row
                for L_I in 1..96
                loop
                    V_CONSUMPTIONS_TS.VOLUME  := round( dbms_random.value( 100, 10000 ) );
                    insert into CONSUMPTIONS_TS values V_CONSUMPTIONS_TS;
                    V_CONSUMPTIONS_TS.AT_VTD  := V_CONSUMPTIONS_TS.AT_VTD - ( V_CONSUMPTIONS_TS.LEN / 96 );
                end loop;

            end if;

        end loop;

        commit;

    end loop;
end;
/

exec DBMS_STATS.GATHER_TABLE_STATS ( ownname => SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'), tabname => 'CONSUMPTIONS_TS_TM' );



--------------------------------------------------------------------------------------------------
--   CONSUMPTIONS_TS Views
--------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------
--  Quarter Hourly data view
--------------------------------------------------------------------------------------------------

create or replace view CONSUMPTIONS_TS_QH_VW as
/*  QH */
select CONSUMPTIONS_TS.PERSON_ID  as PERSON_ID
     , CONSUMPTIONS_TS.AT_VTD     as DATA_DATE
     , CONSUMPTIONS_TS.VOLUME     as VOLUME
  from CONSUMPTIONS_TS
 where CONSUMPTIONS_TS.LEN    = 1
union all
/* Higher than QH (hourly, daily, monthly, yearly)*/
select CONSUMPTIONS_TS.PERSON_ID  
     , TM_RULER_QH.RULER_DATE     
     , CONSUMPTIONS_TS.VOLUME / CONSUMPTIONS_TS.LEN  
  from TM_RULER_QH
     , CONSUMPTIONS_TS
 where CONSUMPTIONS_TS.LEN    >  1
   and TM_RULER_QH.RULER_DATE >  CONSUMPTIONS_TS.AT_VTD - ( CONSUMPTIONS_TS.LEN / 96 )
   and TM_RULER_QH.RULER_DATE <= CONSUMPTIONS_TS.AT_VTD
;

--------------------------------------------------------------------------------------------------
--  Hourly data view
--------------------------------------------------------------------------------------------------

create or replace view CONSUMPTIONS_TS_H_VW as
/*  Less than H */
select CONSUMPTIONS_TS.PERSON_ID                                as PERSON_ID
     , trunc( CONSUMPTIONS_TS.AT_VTD  + ( 50 / 1440 ), 'HH24' ) as DATA_DATE
     , sum( CONSUMPTIONS_TS.VOLUME )                            as VOLUME
  from CONSUMPTIONS_TS
 where CONSUMPTIONS_TS.LEN    <  4 
group by CONSUMPTIONS_TS.PERSON_ID
       , trunc( CONSUMPTIONS_TS.AT_VTD  + (  50 / 1440 ), 'HH24' )
union all
/*  Hourly */
select CONSUMPTIONS_TS.PERSON_ID
     , CONSUMPTIONS_TS.AT_VTD
     , CONSUMPTIONS_TS.VOLUME
  from CONSUMPTIONS_TS
 where CONSUMPTIONS_TS.LEN   = 4
union all
/* Higher than hourly (daily, monthly, yearly)*/
select CONSUMPTIONS_TS.PERSON_ID
     , TM_RULER_H.RULER_DATE
     , CONSUMPTIONS_TS.VOLUME / CONSUMPTIONS_TS.LEN 
  from TM_RULER_H
     , CONSUMPTIONS_TS
 where CONSUMPTIONS_TS.LEN   >  4
   and TM_RULER_H.RULER_DATE >  CONSUMPTIONS_TS.AT_VTD - ( CONSUMPTIONS_TS.LEN / 96 )
   and TM_RULER_H.RULER_DATE <= CONSUMPTIONS_TS.AT_VTD
;

--------------------------------------------------------------------------------------------------
-- Daily data view
--------------------------------------------------------------------------------------------------

create or replace view CONSUMPTIONS_TS_D_VW as
/*  Less than D */
select CONSUMPTIONS_TS.PERSON_ID                           as PERSON_ID
     , trunc( CONSUMPTIONS_TS.AT_VTD  + ( 1439 / 1440 ) )  as DATA_DATE
     , sum( CONSUMPTIONS_TS.VOLUME )                       as VOLUME
  from CONSUMPTIONS_TS
 where CONSUMPTIONS_TS.LEN    <  96
group by CONSUMPTIONS_TS.PERSON_ID
       , trunc( CONSUMPTIONS_TS.AT_VTD  + (  1439 / 1440 )  )
union all
/*  Daily */
select CONSUMPTIONS_TS.PERSON_ID
     , CONSUMPTIONS_TS.AT_VTD
     , CONSUMPTIONS_TS.VOLUME
  from CONSUMPTIONS_TS
 where CONSUMPTIONS_TS.LEN   = 96
union all
/* Higher than daily ( monthly, yearly)*/
select CONSUMPTIONS_TS.PERSON_ID
     , TM_RULER_H.RULER_DATE
     , CONSUMPTIONS_TS.VOLUME / CONSUMPTIONS_TS.LEN 
  from TM_RULER_H
     , CONSUMPTIONS_TS
 where CONSUMPTIONS_TS.LEN   >  96
   and TM_RULER_H.RULER_DATE >  CONSUMPTIONS_TS.AT_VTD - ( CONSUMPTIONS_TS.LEN / 96 )
   and TM_RULER_H.RULER_DATE <= CONSUMPTIONS_TS.AT_VTD
;


--------------------------------------------------------------------------------------------------
--  Monthly data view
--------------------------------------------------------------------------------------------------

create or replace view CONSUMPTIONS_TS_M_VW as
/*  Less than monthly */
select CONSUMPTIONS_TS.PERSON_ID                                              as PERSON_ID
     , trunc( add_months( CONSUMPTIONS_TS.AT_VTD, 1 ) - ( 1 / 1440 ), 'MM' )  as DATA_DATE
     , sum( CONSUMPTIONS_TS.VOLUME )                                          as VOLUME
  from CONSUMPTIONS_TS
 where CONSUMPTIONS_TS.LEN    <  2600
group by CONSUMPTIONS_TS.PERSON_ID
       , trunc( add_months( CONSUMPTIONS_TS.AT_VTD, 1 ) - ( 1 / 1440 ), 'MM' )
union all
/*  Monthly */
select CONSUMPTIONS_TS.PERSON_ID
     , CONSUMPTIONS_TS.AT_VTD
     , CONSUMPTIONS_TS.VOLUME
  from CONSUMPTIONS_TS
 where CONSUMPTIONS_TS.LEN between 2600 and 3000
union all
/* Higher than monthly  */
select CONSUMPTIONS_TS.PERSON_ID
     , TM_RULER_H.RULER_DATE
     , CONSUMPTIONS_TS.VOLUME / CONSUMPTIONS_TS.LEN 
  from TM_RULER_H
     , CONSUMPTIONS_TS
 where CONSUMPTIONS_TS.LEN   >  3000
   and TM_RULER_H.RULER_DATE >  CONSUMPTIONS_TS.AT_VTD - ( CONSUMPTIONS_TS.LEN / 96 )
   and TM_RULER_H.RULER_DATE <= CONSUMPTIONS_TS.AT_VTD
;




--------------------------------------------------------------------------------------------------
--   AMOUNT views Views
--------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------
--  Quarter Amount view
--------------------------------------------------------------------------------------------------

create or replace view CONSUMPTION_AMOUNT_TS_QH_VW as
select PERSON_ID
     , DATA_DATE
     , VOLUME * PRICE as AMOUNT
 from  CONSUMPTIONS_TS_QH_VW 
     , PRICES_QH_VW
 where DATA_DATE = RULER_DATE   
;

--------------------------------------------------------------------------------------------------
--  Hourly data view
--------------------------------------------------------------------------------------------------
create or replace view CONSUMPTION_AMOUNT_TS_H_VW as
select PERSON_ID
     , DATA_DATE
     , VOLUME * PRICE as AMOUNT
 from  CONSUMPTIONS_TS_H_VW 
     , PRICES_H_VW
 where DATA_DATE = RULER_DATE   
;

--------------------------------------------------------------------------------------------------
-- Daily data view
--------------------------------------------------------------------------------------------------

create or replace view CONSUMPTION_AMOUNT_TS_D_VW as
select PERSON_ID
     , DATA_DATE
     , VOLUME * PRICE as AMOUNT
 from  CONSUMPTIONS_TS_D_VW 
     , PRICES_D_VW
 where DATA_DATE = RULER_DATE   
;

--------------------------------------------------------------------------------------------------
--  Monthly data view
--------------------------------------------------------------------------------------------------

create or replace view CONSUMPTION_AMOUNT_TS_M_VW as
select PERSON_ID
     , DATA_DATE
     , VOLUME * PRICE as AMOUNT
 from  CONSUMPTIONS_TS_M_VW 
     , PRICES_M_VW
 where DATA_DATE = RULER_DATE   
;
