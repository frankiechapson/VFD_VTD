 
/*

   "rulers"

*/

--------------------------------------------------------------------------------------------------

DROP TABLE TM_RULER_QH;  -- quarter hourly
DROP TABLE TM_RULER_H;   -- hourly
DROP TABLE TM_RULER_D;   -- daily
DROP TABLE TM_RULER_M;   -- monthly
DROP TABLE TM_RULER_Y;   -- yearly



Prompt *****************************************************************
Prompt **                        R U L E R S                          **
Prompt *****************************************************************


/*============================================================================================*/
CREATE TABLE TM_RULER_QH (
/*============================================================================================*/
    RULER_DATE                      DATE       NOT NULL,
    CONSTRAINT TM_RULER_QH_PK  PRIMARY KEY ( RULER_DATE )
) ORGANIZATION INDEX;
CREATE INDEX TM_RULER_QH_IDX1 ON TM_RULER_QH ( trunc( RULER_DATE, 'fmhh24' ) );
CREATE INDEX TM_RULER_QH_IDX2 ON TM_RULER_QH ( trunc( RULER_DATE           ) );
CREATE INDEX TM_RULER_QH_IDX3 ON TM_RULER_QH ( trunc( RULER_DATE, 'fmmm'   ) );
CREATE INDEX TM_RULER_QH_IDX4 ON TM_RULER_QH ( trunc( RULER_DATE, 'fmyy'   ) );


declare

    V_FROM_DATE   date    := TM_FIRST;
    V_TO_DATE     date    := TM_LAST;
    V_STEP_BY     number  := 1/24/4;

    type T_DATE_LIST is table of date;
    V_DATE_LIST   T_DATE_LIST := new T_DATE_LIST();
begin
    loop
        V_DATE_LIST.extend;
        V_DATE_LIST(V_DATE_LIST.count) := V_FROM_DATE;
        V_FROM_DATE := V_FROM_DATE + V_STEP_BY;
        exit when V_FROM_DATE > V_TO_DATE;
    end loop;
    forall L_I in V_DATE_LIST.first..V_DATE_LIST.last
        insert into TM_RULER_QH ( RULER_DATE ) values ( V_DATE_LIST(L_I) ); 
    commit;
end;
/


/*============================================================================================*/
CREATE TABLE TM_RULER_H (
/*============================================================================================*/
    RULER_DATE                      DATE       NOT NULL,
    CONSTRAINT TM_RULER_H_PK  PRIMARY KEY ( RULER_DATE )
) ORGANIZATION INDEX;
CREATE INDEX TM_RULER_H_IDX1 ON TM_RULER_H ( trunc( RULER_DATE           ) );
CREATE INDEX TM_RULER_H_IDX2 ON TM_RULER_H ( trunc( RULER_DATE, 'fmmm'   ) );
CREATE INDEX TM_RULER_H_IDX3 ON TM_RULER_H ( trunc( RULER_DATE, 'fmyy'   ) );


declare

    V_FROM_DATE   date    := TM_FIRST;
    V_TO_DATE     date    := TM_LAST;
    V_STEP_BY     number  := 1/24;

    type T_DATE_LIST is table of date;
    V_DATE_LIST   T_DATE_LIST := new T_DATE_LIST();
begin
    loop
        V_DATE_LIST.extend;
        V_DATE_LIST(V_DATE_LIST.count) := V_FROM_DATE;
        V_FROM_DATE := V_FROM_DATE + V_STEP_BY;
        exit when V_FROM_DATE > V_TO_DATE;
    end loop;
    forall L_I in V_DATE_LIST.first..V_DATE_LIST.last
        insert into TM_RULER_H ( RULER_DATE ) values ( V_DATE_LIST(L_I) ); 
    commit;
end;
/


/*============================================================================================*/
CREATE TABLE TM_RULER_D (
/*============================================================================================*/
    RULER_DATE                      DATE       NOT NULL,
    CONSTRAINT TM_RULER_D_PK  PRIMARY KEY ( RULER_DATE )
) ORGANIZATION INDEX;
CREATE INDEX TM_RULER_D_IDX1 ON TM_RULER_D ( trunc( RULER_DATE, 'fmmm'   ) );
CREATE INDEX TM_RULER_D_IDX2 ON TM_RULER_D ( trunc( RULER_DATE, 'fmyy'   ) );


declare

    V_FROM_DATE   date    := TM_FIRST;
    V_TO_DATE     date    := TM_LAST;
    V_STEP_BY     number  := 1;

    type T_DATE_LIST is table of date;
    V_DATE_LIST   T_DATE_LIST := new T_DATE_LIST();
begin
    loop
        V_DATE_LIST.extend;
        V_DATE_LIST(V_DATE_LIST.count) := V_FROM_DATE;
        V_FROM_DATE := V_FROM_DATE + V_STEP_BY;
        exit when V_FROM_DATE > V_TO_DATE;
    end loop;
    forall L_I in V_DATE_LIST.first..V_DATE_LIST.last
        insert into TM_RULER_D ( RULER_DATE ) values ( V_DATE_LIST(L_I) ); 
    commit;
end;
/


/*============================================================================================*/
CREATE TABLE TM_RULER_M (
/*============================================================================================*/
    RULER_DATE                      DATE       NOT NULL,
    CONSTRAINT TM_RULER_M_PK  PRIMARY KEY ( RULER_DATE )
) ORGANIZATION INDEX;
CREATE INDEX TM_RULER_M_IDX1 ON TM_RULER_M ( trunc( RULER_DATE, 'fmyy'   ) );


declare

    V_FROM_DATE   date    := TM_FIRST;
    V_TO_DATE     date    := TM_LAST;
    V_STEP_BY     number  := 1;

    type T_DATE_LIST is table of date;
    V_DATE_LIST   T_DATE_LIST := new T_DATE_LIST();
begin
    loop
        V_DATE_LIST.extend;
        V_DATE_LIST(V_DATE_LIST.count) := V_FROM_DATE;
        V_FROM_DATE := add_months(V_FROM_DATE, V_STEP_BY);
        exit when V_FROM_DATE > V_TO_DATE;
    end loop;
    forall L_I in V_DATE_LIST.first..V_DATE_LIST.last
        insert into TM_RULER_M ( RULER_DATE ) values ( V_DATE_LIST(L_I) ); 
    commit;
end;
/

/*============================================================================================*/
CREATE TABLE TM_RULER_Y (
/*============================================================================================*/
    RULER_DATE                      DATE       NOT NULL,
    CONSTRAINT TM_RULER_Y_PK  PRIMARY KEY ( RULER_DATE )
) ORGANIZATION INDEX;

declare

    V_FROM_DATE   date    := TM_FIRST;
    V_TO_DATE     date    := TM_LAST;
    V_STEP_BY     number  := 12;

    type T_DATE_LIST is table of date;
    V_DATE_LIST   T_DATE_LIST := new T_DATE_LIST();
begin
    loop
        V_DATE_LIST.extend;
        V_DATE_LIST(V_DATE_LIST.count) := V_FROM_DATE;
        V_FROM_DATE := add_months(V_FROM_DATE, V_STEP_BY);
        exit when V_FROM_DATE > V_TO_DATE;
    end loop;
    forall L_I in V_DATE_LIST.first..V_DATE_LIST.last
        insert into TM_RULER_Y ( RULER_DATE ) values ( V_DATE_LIST(L_I) ); 
    commit;
end;
/

exec DBMS_STATS.GATHER_TABLE_STATS ( ownname => SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'), tabname => 'TM_RULER_QH' );
exec DBMS_STATS.GATHER_TABLE_STATS ( ownname => SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'), tabname => 'TM_RULER_H'  );
exec DBMS_STATS.GATHER_TABLE_STATS ( ownname => SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'), tabname => 'TM_RULER_D'  );
exec DBMS_STATS.GATHER_TABLE_STATS ( ownname => SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'), tabname => 'TM_RULER_M'  );
exec DBMS_STATS.GATHER_TABLE_STATS ( ownname => SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'), tabname => 'TM_RULER_Y'  );


