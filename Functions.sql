-------------------------------------------------------

create or replace package PKG_TM as
    G_NOW       date;   -- session level global variable for "NOW"
    G_AT        date;   -- session level global variable for "AT"
end;
/    

-------------------------------------------------------

create or replace function TM_RESOL ( I_DATE in date := sysdate ) return number deterministic is  
-- the resolution in day. Two date are identical within the resolution (period)
begin
--  return 1/86400;                             -- second
--  return 1/1440;                              -- minute
--  return 1/24;                                -- hour
    return 1;                                   -- day
--  return last_day( I_DATE );                  -- month
--  return add_months( trunc( I_DATE, 'YYYY' ), 12 ) - trunc( I_DATE, 'YYYY' );                  -- year
end;
/


-------------------------------------------------------

create or replace function TM_TRUNC_DATE ( I_DATE in date := null) return date is           
-- trunc date/time according to resolution
begin
    if TM_RESOL = 1/86400 then
        return I_DATE;                              -- second

    elsif TM_RESOL = 1/1440 then
        return trunc( I_DATE, 'MI');                -- minute

    elsif TM_RESOL = 1/24 then
        return trunc( I_DATE, 'HH24');              -- hour

    elsif TM_RESOL = 1 then
        return trunc( I_DATE, 'DD');                -- day

    elsif TM_RESOL <= 31 then
        return trunc( I_DATE, 'MM');                -- month

    else
        return trunc( I_DATE, 'YYYY');              -- year
    end if;
end;
/

-------------------------------------------------------

create or replace procedure TM_SET_NOW ( I_NOW in date := null) is  
-- this set up the "NOW" to a certain value or to null = sysdate and it is passing!
begin
    PKG_TM.G_NOW := TM_TRUNC_DATE ( I_NOW );  
end;
/

-------------------------------------------------------

create or replace procedure TM_SET_AT ( I_AT in date := null) is  
-- this set up the "AT" to a certain value or to null = sysdate and it is passing!
begin
    PKG_TM.G_AT := TM_TRUNC_DATE ( I_AT );  
end;
/

-------------------------------------------------------

create or replace function TM_RIGHT_NOW return date is            
begin
    return TM_TRUNC_DATE ( sysdate );               
end;
/

-------------------------------------------------------


create or replace function TM_NOW return date deterministic is         
-- returns with the set up (constant) "NOW" or current (passing) time
begin
    return nvl( PKG_TM.G_NOW, TM_RIGHT_NOW);     
end;
/

-------------------------------------------------------

create or replace function TM_AT return date deterministic is         
-- returns with the set up (constant) "AT" or current (passing) time
begin
    return nvl( PKG_TM.G_AT, TM_RIGHT_NOW);     
end;
/


-------------------------------------------------------

create or replace function TM_FIRST return date deterministic is 
-- the oldest time
begin
    return to_date('20100101000000','yyyymmddhh24miss');   
end;
/

-------------------------------------------------------

create or replace function TM_LAST return date deterministic is         
-- the highest time
begin
    return to_date('20300101000000','yyyymmddhh24miss');  
end;
/

-------------------------------------------------------


-- short version of pkg_diff
create or replace package PKG_DIFF_VAL as


/* *******************************************************************************************************

    History of changes
    yyyy.mm.dd | Version | Author         | Changes
    -----------+---------+----------------+-------------------------
    2017.01.06 |  1.0    | Ferenc Toth    | Created 

******************************************************************************************************* */


    ------------------------------------------------------------------------------------

    FUNCTION  VALUES_ARE_DIFFER ( i_old_value IN VARCHAR2                   , i_new_value IN VARCHAR2                   ) RETURN BOOLEAN;
    FUNCTION  VALUES_ARE_DIFFER ( i_old_value IN NUMBER                     , i_new_value IN NUMBER                     ) RETURN BOOLEAN;
    FUNCTION  VALUES_ARE_DIFFER ( i_old_value IN DATE                       , i_new_value IN DATE                       ) RETURN BOOLEAN;
    FUNCTION  VALUES_ARE_DIFFER ( i_old_value IN TIMESTAMP                  , i_new_value IN TIMESTAMP                  ) RETURN BOOLEAN;
    FUNCTION  VALUES_ARE_DIFFER ( i_old_value IN TIMESTAMP WITH TIME ZONE   , i_new_value IN TIMESTAMP WITH TIME ZONE   ) RETURN BOOLEAN;

    ------------------------------------------------------------------------------------

end;
/



create or replace package body PKG_DIFF_VAL as

/* *******************************************************************************************************

    History of changes
    yyyy.mm.dd | Version | Author         | Changes
    -----------+---------+----------------+-------------------------
    2017.01.06 |  1.0    | Ferenc Toth    | Created 

******************************************************************************************************* */

    ------------------------------------------------------------------------------------

    FUNCTION  VALUES_ARE_DIFFER ( i_old_value IN VARCHAR2, i_new_value IN VARCHAR2 ) RETURN BOOLEAN IS
    BEGIN
        IF (i_old_value IS NOT NULL AND i_new_value IS     NULL) OR
           (i_old_value IS     NULL AND i_new_value IS NOT NULL) OR
           (i_old_value IS NOT NULL AND i_new_value IS NOT NULL  AND i_old_value <> i_new_value ) THEN
          RETURN TRUE;
        END IF;
        RETURN FALSE;
    END;
   
    FUNCTION  VALUES_ARE_DIFFER ( i_old_value IN NUMBER, i_new_value IN NUMBER ) RETURN BOOLEAN IS
    BEGIN
        IF (i_old_value IS NOT NULL AND i_new_value IS     NULL) OR
           (i_old_value IS     NULL AND i_new_value IS NOT NULL) OR
           (i_old_value IS NOT NULL AND i_new_value IS NOT NULL  AND i_old_value <> i_new_value ) THEN
          RETURN TRUE;
        END IF;
        RETURN FALSE;
    END;
   
    FUNCTION  VALUES_ARE_DIFFER ( i_old_value IN DATE, i_new_value IN DATE ) RETURN BOOLEAN IS
    BEGIN
        IF (i_old_value IS NOT NULL AND i_new_value IS     NULL) OR
           (i_old_value IS     NULL AND i_new_value IS NOT NULL) OR
           (i_old_value IS NOT NULL AND i_new_value IS NOT NULL  AND i_old_value <> i_new_value ) THEN
          RETURN TRUE;
        END IF;
        RETURN FALSE;
    END;
   
    FUNCTION  VALUES_ARE_DIFFER ( i_old_value IN TIMESTAMP, i_new_value IN TIMESTAMP ) RETURN BOOLEAN IS
    BEGIN
        IF (i_old_value IS NOT NULL AND i_new_value IS     NULL) OR
           (i_old_value IS     NULL AND i_new_value IS NOT NULL) OR
           (i_old_value IS NOT NULL AND i_new_value IS NOT NULL  AND i_old_value <> i_new_value ) THEN
          RETURN TRUE;
        END IF;
        RETURN FALSE;
    END;

    FUNCTION  VALUES_ARE_DIFFER ( i_old_value IN TIMESTAMP WITH TIME ZONE, i_new_value IN TIMESTAMP WITH TIME ZONE ) RETURN BOOLEAN IS
    BEGIN
        IF (i_old_value IS NOT NULL AND i_new_value IS     NULL) OR
           (i_old_value IS     NULL AND i_new_value IS NOT NULL) OR
           (i_old_value IS NOT NULL AND i_new_value IS NOT NULL  AND i_old_value <> i_new_value ) THEN
          RETURN TRUE;
        END IF;
        RETURN FALSE;
    END;

    ------------------------------------------------------------------------------------

end;
/
