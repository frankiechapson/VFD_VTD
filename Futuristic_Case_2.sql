/***********************************************************************************************************/
/*

  2nd case.

  Here is an example how to handle predefined future changes

  This uses the functions and the package from Functions.sql file

    
    -- set the present (time passing)
    exec TM_SET_NOW;
    select * from MEMBERSHIPS;

    -- set any time in the future and see what data will be at that time in MEMBERSHIPS table:
    exec TM_SET_NOW( to_date('2030.01.10','yyyy.mm.dd') );
    select * from MEMBERSHIPS;
    
    -- but we can set any time in the past as well, and see what data were at that time in MEMBERSHIPS table:
    exec TM_SET_NOW( to_date('2010.01.01','yyyy.mm.dd') );
    select * from MEMBERSHIPS;
    

    Here is the implementation:

*/

--------------------------------------------------------------------------------------------------
-- init
--------------------------------------------------------------------------------------------------

drop   table MEMBERSHIPS_TM;
drop   view  MEMBERSHIPS;
create sequence SEQ_ID;

--------------------------------------------------------------------------------------------------

create table MEMBERSHIPS 
    (
      PERSON_ID      NUMBER         not null
    , ROLE           VARCHAR2 ( 100 )
    , AT_VFD         DATE           not null    -- validity period start ( the "AT" will be meaningful later in the "combined" case )
    , AT_VTD         DATE           not null    -- validity period end
    );

create unique index IX1_MEMBERSHIPS on MEMBERSHIPS ( PERSON_ID, AT_VFD );
create        index IX2_MEMBERSHIPS on MEMBERSHIPS ( AT_VFD   , AT_VTD );


--------------------------------------------------------------------------------------------------
-- hide the complexity with views:
--------------------------------------------------------------------------------------------------

alter table MEMBERSHIPS rename to MEMBERSHIPS_TM;

--------------------------------------------------------------------------------------------------
-- we need to see both all changes ...
--------------------------------------------------------------------------------------------------
create or replace view MEMBERSHIPS as 
select PERSON_ID
     , ROLE
     , AT_VFD    
     , AT_VTD    
  from MEMBERSHIPS_TM ;


--------------------------------------------------------------------------------------------------
-- ... and just a time slice too
--------------------------------------------------------------------------------------------------
create or replace view MEMBERSHIP as 
select PERSON_ID
     , ROLE
     , AT_VFD    
     , AT_VTD    
  from MEMBERSHIPS_TM 
 where TM_NOW between AT_VFD and AT_VTD;


--------------------------------------------------------------------------------------------------
-- DELETE
--------------------------------------------------------------------------------------------------

create or replace trigger TR_MEMBERSHIPS_IDR 
  instead of delete on MEMBERSHIPS for each row
declare
    V_RIGHT_NOW       date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW then       

        -- we can delete the future
        if V_RIGHT_NOW - :old.AT_VFD <= TM_RESOL then

            delete MEMBERSHIPS_TM
             where PERSON_ID = :old.PERSON_ID
               and AT_VFD    = :old.AT_VFD;

        else
            -- can not the present and past
            RAISE_APPLICATION_ERROR( -20003, 'The past can not change!' );
        end if;

    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be deleted in real time (right now) only! Use TM_SET_NOW(null)!');
    end if;
end;
/

--------------------------------------------------------------------------------------------------
-- INSERT
--------------------------------------------------------------------------------------------------

create or replace trigger TR_MEMBERSHIPS_IIR 
  instead of insert on MEMBERSHIPS for each row
declare
    V_CNT             number;
    V_MEMBERSHIPS_TM  MEMBERSHIPS_TM%rowtype;
    V_RIGHT_NOW       date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW then       

        -- if there is not start date, then start from now
        V_MEMBERSHIPS_TM.AT_VFD := nvl( TM_TRUNC_DATE( :new.AT_VFD ), V_RIGHT_NOW );

        if V_MEMBERSHIPS_TM.AT_VFD >= V_RIGHT_NOW then
        -- we can define changes only for future

            -- if there is not end, then never end
            V_MEMBERSHIPS_TM.AT_VTD := nvl( TM_TRUNC_DATE( :new.AT_VTD ), TM_LAST  );

            if V_MEMBERSHIPS_TM.AT_VTD >= V_MEMBERSHIPS_TM.AT_VFD then

                V_MEMBERSHIPS_TM.PERSON_ID := :new.PERSON_ID;
                V_MEMBERSHIPS_TM.ROLE      := :new.ROLE;

                -- check overlaps!
                select count(*) 
                  into V_CNT
                  from MEMBERSHIPS_TM
                 where AT_VFD   <= V_MEMBERSHIPS_TM.AT_VTD
                   and AT_VTD   >= V_MEMBERSHIPS_TM.AT_VFD
                   and PERSON_ID = V_MEMBERSHIPS_TM.PERSON_ID;

                if V_CNT = 0 then
                    -- there is not overlappings, so we can insert it
                    insert into MEMBERSHIPS_TM values V_MEMBERSHIPS_TM;
                else
                    RAISE_APPLICATION_ERROR( -20002, 'Not allowed to insert data with overlapping periods!');
                end if;

            else
                RAISE_APPLICATION_ERROR( -20004, 'The start date must be less then the end date!' );
            end if;

        else
            RAISE_APPLICATION_ERROR( -20003, 'The past can not change!' );
        end if;

    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be inserted in real time (right now) only! Use TM_SET_NOW(null)!');
    end if;
end;
/

--------------------------------------------------------------------------------------------------
-- UPDATE
--------------------------------------------------------------------------------------------------

create or replace trigger TR_MEMBERSHIPS_IUR 
  instead of update on MEMBERSHIPS for each row
declare
    V_CNT             number;
    V_MEMBERSHIPS_TM  MEMBERSHIPS_TM%rowtype;
    V_RIGHT_NOW       date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW then       
        
        V_MEMBERSHIPS_TM.AT_VFD := nvl( TM_TRUNC_DATE( :new.AT_VFD ), :old.AT_VFD );  -- if there is not a new value, then leave the old one
        V_MEMBERSHIPS_TM.AT_VTD := nvl( TM_TRUNC_DATE( :new.AT_VTD ), TM_LAST     );  -- if there is not a new value, then forever

        -- The future can change but only if stayed in the future (max you close the validity now)
        if  ( :old.AT_VTD >= V_RIGHT_NOW and V_MEMBERSHIPS_TM.AT_VTD >= V_RIGHT_NOW and :old.AT_VFD = V_MEMBERSHIPS_TM.AT_VFD ) then

            if V_MEMBERSHIPS_TM.AT_VTD >= V_MEMBERSHIPS_TM.AT_VFD then

                V_MEMBERSHIPS_TM.PERSON_ID := :new.PERSON_ID;
                V_MEMBERSHIPS_TM.ROLE      := :new.ROLE;

                -- ...relevant data has changed?
                if PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.PERSON_ID , V_MEMBERSHIPS_TM.PERSON_ID ) 
                or PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.AT_VTD    , V_MEMBERSHIPS_TM.AT_VTD    ) 
                or PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.ROLE      , V_MEMBERSHIPS_TM.ROLE      ) 
                then
                
                    -- check overlaps!
                    select count(*) 
                      into V_CNT
                      from MEMBERSHIPS_TM
                     where AT_VFD       <= V_MEMBERSHIPS_TM.AT_VTD
                       and AT_VTD       >= V_MEMBERSHIPS_TM.AT_VFD
                       and AT_VFD       != :old.AT_VFD
                       and AT_VTD       != :old.AT_VTD
                       and PERSON_ID     = V_MEMBERSHIPS_TM.PERSON_ID;

                    if V_CNT = 0 then
                        update MEMBERSHIPS_TM 
                           set PERSON_ID = V_MEMBERSHIPS_TM.PERSON_ID
                             , ROLE      = V_MEMBERSHIPS_TM.ROLE
                             , AT_VTD    = V_MEMBERSHIPS_TM.AT_VTD
                         where PERSON_ID = :old.PERSON_ID
                           and AT_VFD    = :old.AT_VFD;
                    else
                        RAISE_APPLICATION_ERROR( -20002, 'Not allowed to update data with overlapping periods!');
                    end if;

                else
                    -- here is the simple update part of non-relevant data changes
                    null;
                end if;

            else
                RAISE_APPLICATION_ERROR( -20004, 'The start date must be less then the end date!' );
            end if;

        else
            RAISE_APPLICATION_ERROR( -20003, 'The past can not change!' );
        end if;

    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be updates in real time (right now) only! Use TM_SET_NOW(null)!');
    end if;
end;
/


--------------------------------------------------------------------------------------------------

