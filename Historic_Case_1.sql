/***********************************************************************************************************/

/*

  1st case.

  Here is an example how to handle historical changes

  This uses the functions and the package from Functions.sql file

    
    -- set the present (time passing)
    exec TM_SET_NOW;
    select * from PERSONS    order by NAME;

    -- set any time in past and see what data were at that time in PERSONS table:
    exec TM_SET_NOW( to_date('2016.08.20','yyyy.mm.dd') );
    select * from PERSONS    order by NAME;

    Here is the implementation:

*/

-- init

drop   table PERSONS_TM;
drop   view  PERSONS;
create sequence SEQ_ID;

--------------------------------------------------------------------------------------------------
-- Here is a simple table in original form:
--------------------------------------------------------------------------------------------------

create table PERSONS 
    (
      ID                NUMBER          not null     
    , NAME              VARCHAR2( 100 ) not null     
    , POB               VARCHAR2( 100 )              
    , USER_NAME         VARCHAR2( 100 ) not null     
    , POSITION          VARCHAR2( 100 )              
    , REMARK            VARCHAR2( 100 )             
    , CRE_USR           VARCHAR2( 100 ) not null     
    , MOD_USR           VARCHAR2( 100 ) not null     
    );

create unique index IX1_PERSONS on PERSONS ( ID        );
create unique index IX2_PERSONS on PERSONS ( USER_NAME );


--------------------------------------------------------------------------------------------------
-- Let's treat it historical managed!
--------------------------------------------------------------------------------------------------
drop   table PERSONS;
create table PERSONS 
    (
      ID                NUMBER          not null      -- Internal PK. Can not change! Unique with the NOW_VFD together.
    , NAME              VARCHAR2( 100 ) not null      -- It can change ( eg. typo )
    , POB               VARCHAR2( 100 )               -- It can change ( eg. typo )
    , USER_NAME         VARCHAR2( 100 ) not null      -- It can not change and this is business key. Unique with the NOW_VFD together too.
    , POSITION          VARCHAR2( 100 )               -- It can change
    , REMARK            VARCHAR2( 100 )               -- It can change, but not relevant. We do not want to log changes of it
    , CRE_USR           VARCHAR2( 100 ) not null      -- It can not change
    , MOD_USR           VARCHAR2( 100 ) not null      -- It can change normaly, but not in this case. See later
    ------------------------------------------------------
    , NOW_VFD           DATE            not null      -- validity period start ( the "NOW" will be meaningful later in the "combined" case )
    , NOW_VTD           DATE            not null      -- validity period end
    ------------------------------------------------------
    );

create unique index IX1_PERSONS on PERSONS ( ID        , NOW_VFD );
create unique index IX2_PERSONS on PERSONS ( USER_NAME , NOW_VFD );
create        index IX3_PERSONS on PERSONS ( NOW_VFD   , NOW_VTD );

--------------------------------------------------------------------------------------------------
-- Hide the complexity with a view:
--------------------------------------------------------------------------------------------------

alter table PERSONS rename to PERSONS_TM;

--------------------------------------------------------------------------------------------------
-- These are still for the table
--------------------------------------------------------------------------------------------------

create or replace trigger TR_PERSONS_TM_BIR 
  before insert on PERSONS_TM for each row
begin
    :new.ID      := nvl( :new.ID, SEQ_ID.nextval );
    :new.CRE_USR := nvl( :new.CRE_USR, USER );
    :new.MOD_USR := USER;
end;
/

create or replace trigger TR_PERSONS_TM_BUR 
  before update on PERSONS_TM for each row
begin
    :new.MOD_USR := USER;
end;
/


--------------------------------------------------------------------------------------------------
-- From this point we will use View instead of Table:
--------------------------------------------------------------------------------------------------
-- the PERSONS view allways shows the data at TM_NOW!  

create or replace view PERSONS as 
select ID           
     , NAME             
     , POB              
     , USER_NAME        
     , POSITION         
     , REMARK         
     , CRE_USR          
     , MOD_USR          
  from PERSONS_TM 
 where TM_NOW between NOW_VFD and NOW_VTD;


--------------------------------------------------------------------------------------------------
-- DELETE
--------------------------------------------------------------------------------------------------

create or replace trigger TR_PERSONS_IDR 
  instead of delete on PERSONS for each row
declare
    V_OLD_VFD         date;
    V_RIGHT_NOW       date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW then       

        select max( NOW_VFD )
          into V_OLD_VFD
          from PERSONS_TM
         where ID = :old.ID;

        -- If we are within the resolution, then it will be a real delete
        if V_RIGHT_NOW - V_OLD_VFD <= TM_RESOL then

            delete PERSONS_TM 
             where ID  = :old.ID
               and V_RIGHT_NOW between NOW_VFD and NOW_VTD;

        else
            -- in other cases it will be period close without a new one
            update PERSONS_TM 
               set NOW_VTD = V_RIGHT_NOW - TM_RESOL    
             where ID  = :old.ID
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

create or replace trigger TR_PERSONS_IIR 
  instead of insert on PERSONS for each row
declare
    V_CNT           number;
    V_PERSONS_TM    PERSONS_TM%rowtype;
    V_RIGHT_NOW     date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW then       

        -- has this USER_NAME already exist?  ( check unique constraint )
        select count(*)
          into V_CNT
          from PERSONS_TM
         where USER_NAME = :new.USER_NAME;

        if V_CNT = 0 then

            -- has this ID already exist?  ( check unique constraint )
            select count(*)
              into V_CNT
              from PERSONS_TM
             where ID = :new.ID;

            if V_CNT = 0 then
                -- Not, so we can insert the new data row
                V_PERSONS_TM.ID         := :new.ID;
                V_PERSONS_TM.NAME       := :new.NAME;
                V_PERSONS_TM.USER_NAME  := :new.USER_NAME;
                V_PERSONS_TM.POSITION   := :new.POSITION;
                V_PERSONS_TM.REMARK     := :new.REMARK;
                V_PERSONS_TM.POB        := :new.POB;
                V_PERSONS_TM.NOW_VFD    := V_RIGHT_NOW;
                V_PERSONS_TM.NOW_VTD    := TM_LAST;
                insert into PERSONS_TM values V_PERSONS_TM;

            else
                RAISE_APPLICATION_ERROR( -20002, 'This ID has already exist. The ID must be unique.' );
            end if;

        else
            RAISE_APPLICATION_ERROR( -20002, 'This USER_NAME has already exist. The USER_NAME must be unique.' );
        end if;

    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be inserted in real time (right now) only! Use TM_SET_NOW(null)! ' );
    end if;

end;
/

--------------------------------------------------------------------------------------------------
-- UPDATE
--------------------------------------------------------------------------------------------------

create or replace trigger TR_PERSONS_IUR 
  instead of update on PERSONS for each row
declare
    V_CNT             number;
    V_PERSONS_TM      PERSONS_TM%rowtype;
    V_OLD_VFD         date;
    V_RIGHT_NOW       date := TM_RIGHT_NOW;
begin
    if TM_NOW = TM_RIGHT_NOW then       

        -- the ID can not change!
        if :old.ID = :new.ID then

            -- the USER_NAME can not change!
            if :old.USER_NAME = :new.USER_NAME then

                -- ...is there any real (relevant data) change? 
                if PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.NAME    , :new.NAME     ) 
                or PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.POSITION, :new.POSITION ) 
                or PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.POB     , :new.POB      ) 
                then

                    -- if we are within the resolution it will be a normal update, because we can not create a new time period 
                    select max( NOW_VFD )
                      into V_OLD_VFD
                      from PERSONS_TM
                     where ID = :new.ID;

                    if V_RIGHT_NOW - V_OLD_VFD <= TM_RESOL then

                        update PERSONS_TM 
                           set NAME       = :new.NAME
                             , POSITION   = :new.POSITION
                             , POB        = :new.POB
                         where ID         = :new.ID
                           and V_RIGHT_NOW between NOW_VFD and NOW_VTD;

                    else
                    -- otherwise we logging the change
                        -- close the current data
                        update PERSONS_TM 
                           set NOW_VTD = V_RIGHT_NOW - TM_RESOL
                         where ID  = :new.ID
                           and V_RIGHT_NOW between NOW_VFD and NOW_VTD;
                        -- and insert the new one
                        if sql%rowcount = 1 then
                            V_PERSONS_TM.ID         := :new.ID;
                            V_PERSONS_TM.NAME       := :new.NAME;
                            V_PERSONS_TM.USER_NAME  := :new.USER_NAME;
                            V_PERSONS_TM.POSITION   := :new.POSITION;
                            V_PERSONS_TM.REMARK     := :new.REMARK;
                            V_PERSONS_TM.POB        := :new.POB;
                            V_PERSONS_TM.CRE_USR    := :old.CRE_USR;
                            V_PERSONS_TM.NOW_VFD    := V_RIGHT_NOW;
                            V_PERSONS_TM.NOW_VTD    := TM_LAST;
                            insert into PERSONS_TM values V_PERSONS_TM;
                        end if;

                    end if;

                else
                    -- here we can handle not relevant data changes
                    -- this will be a simple update without logging
                    if PKG_DIFF_VAL.VALUES_ARE_DIFFER( :old.REMARK, :new.REMARK ) then

                        update PERSONS_TM 
                           set REMARK = :new.REMARK
                         where ID     = :new.ID
                           and V_RIGHT_NOW between NOW_VFD and NOW_VTD;

                    end if;

                end if;

            else
                RAISE_APPLICATION_ERROR( -20003, 'The USER_NAME can not change!' );
            end if;

        else
            RAISE_APPLICATION_ERROR( -20003, 'The ID can not change!' );
        end if;
  
    else
        RAISE_APPLICATION_ERROR( -20001, 'Data can be updated in real time (right now) only! Use TM_SET_NOW(null)!' );
    end if;
end;
/

----------------------------------------------------------------------------------------
