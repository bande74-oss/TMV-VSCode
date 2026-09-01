USE [master];
CREATE LOGIN [mcp_reader] WITH PASSWORD = N'TuaPasswordSicura123!', CHECK_POLICY = OFF;
GO

USE [DBTMV]; -- Il nome del tuo database locale
CREATE USER [mcp_reader] FOR LOGIN [mcp_reader];
ALTER ROLE [db_datareader] ADD MEMBER [mcp_reader];
GO