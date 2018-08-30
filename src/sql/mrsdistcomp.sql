USE [master]
GO

/****** Object:  Database [MLSDISTCOMP]    Script Date: 10/6/2017 2:58:03 PM ******/
CREATE DATABASE [MLSDISTCOMP]
 CONTAINMENT = NONE
 ON  PRIMARY 
( NAME = N'MLSDistcomp', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\MLSDistcomp.mdf' , SIZE = 8192KB , MAXSIZE = UNLIMITED, FILEGROWTH = 65536KB )
 LOG ON 
( NAME = N'MLSDistcomp_log', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\MLSDistcomp_log.ldf' , SIZE = 8192KB , MAXSIZE = 2048GB , FILEGROWTH = 65536KB )
GO

ALTER DATABASE [MLSDISTCOMP] SET COMPATIBILITY_LEVEL = 130
GO

IF (1 = FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'))
begin
EXEC [MLSDISTCOMP].[dbo].[sp_fulltext_database] @action = 'enable'
end
GO

ALTER DATABASE [MLSDISTCOMP] SET ANSI_NULL_DEFAULT OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET ANSI_NULLS OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET ANSI_PADDING OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET ANSI_WARNINGS OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET ARITHABORT OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET AUTO_CLOSE OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET AUTO_SHRINK OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET AUTO_UPDATE_STATISTICS ON 
GO

ALTER DATABASE [MLSDISTCOMP] SET CURSOR_CLOSE_ON_COMMIT OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET CURSOR_DEFAULT  GLOBAL 
GO

ALTER DATABASE [MLSDISTCOMP] SET CONCAT_NULL_YIELDS_NULL OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET NUMERIC_ROUNDABORT OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET QUOTED_IDENTIFIER OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET RECURSIVE_TRIGGERS OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET  DISABLE_BROKER 
GO

ALTER DATABASE [MLSDISTCOMP] SET AUTO_UPDATE_STATISTICS_ASYNC OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET DATE_CORRELATION_OPTIMIZATION OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET TRUSTWORTHY OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET ALLOW_SNAPSHOT_ISOLATION OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET PARAMETERIZATION SIMPLE 
GO

ALTER DATABASE [MLSDISTCOMP] SET READ_COMMITTED_SNAPSHOT OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET HONOR_BROKER_PRIORITY OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET RECOVERY FULL 
GO

ALTER DATABASE [MLSDISTCOMP] SET  MULTI_USER 
GO

ALTER DATABASE [MLSDISTCOMP] SET PAGE_VERIFY CHECKSUM  
GO

ALTER DATABASE [MLSDISTCOMP] SET DB_CHAINING OFF 
GO

ALTER DATABASE [MLSDISTCOMP] SET FILESTREAM( NON_TRANSACTED_ACCESS = OFF ) 
GO

ALTER DATABASE [MLSDISTCOMP] SET TARGET_RECOVERY_TIME = 60 SECONDS 
GO

ALTER DATABASE [MLSDISTCOMP] SET DELAYED_DURABILITY = DISABLED 
GO

ALTER DATABASE [MLSDISTCOMP] SET QUERY_STORE = OFF
GO

USE [MLSDISTCOMP]
GO

ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;
GO

ALTER DATABASE SCOPED CONFIGURATION FOR SECONDARY SET MAXDOP = PRIMARY;
GO

ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF;
GO

ALTER DATABASE SCOPED CONFIGURATION FOR SECONDARY SET LEGACY_CARDINALITY_ESTIMATION = PRIMARY;
GO

ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = ON;
GO

ALTER DATABASE SCOPED CONFIGURATION FOR SECONDARY SET PARAMETER_SNIFFING = PRIMARY;
GO

ALTER DATABASE SCOPED CONFIGURATION SET QUERY_OPTIMIZER_HOTFIXES = OFF;
GO

ALTER DATABASE SCOPED CONFIGURATION FOR SECONDARY SET QUERY_OPTIMIZER_HOTFIXES = PRIMARY;
GO

ALTER DATABASE [MLSDISTCOMP] SET  READ_WRITE 
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/*
****** DROP TABLES ******
*/

DROP TABLE IF EXISTS [dbo].[ComputationInfoJob]
DROP TABLE IF EXISTS [dbo].[ComputationInfoParticipants]
DROP TABLE IF EXISTS [dbo].[ComputationInfo]
DROP TABLE IF EXISTS [dbo].[DataSources]
DROP TABLE IF EXISTS [dbo].[DataCatalog]
DROP TABLE IF EXISTS [dbo].[Participants]
DROP TABLE IF EXISTS [dbo].[AvailableComputation]
GO

/*
****** CREATE Table [dbo].[DataCatalog] ******
*/

CREATE TABLE [dbo].[DataCatalog](
	[Id] [uniqueidentifier] NOT NULL,
	[Name] [varchar](50) NOT NULL,
	[Description] [varchar](1024) NULL,
	[Version] [varchar](15) NOT NULL,		
	[SchemaJSON] [varchar](max) NULL,
	[SchemaBin] [ntext] NULL,
	CONSTRAINT [PK_DataCatalog] PRIMARY KEY CLUSTERED 
	(
		[Name] ASC		
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
	CONSTRAINT AK_DataCatalog_ID UNIQUE([Id]) 
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO


/*
****** CREATE Table [dbo].[DataSources] ******
*/

CREATE TABLE [dbo].[DataSources](
	[Id] [uniqueidentifier] NOT NULL,
	[Name] [varchar](50) NOT NULL,
	[Description] [varchar](1024) NULL,
	[Type] [varchar](15) NOT NULL,	
	[DataCatalog] [varchar](50) NOT NULL,
	[AccessInfo] [varchar](max) NOT NULL,
	[IsEnabled] [bit] NOT NULL,
	CONSTRAINT [PK_DataSources] PRIMARY KEY CLUSTERED 
	(
		[Name] ASC		
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
	CONSTRAINT AK_DataSources_ID UNIQUE([Id]) 
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO

ALTER TABLE [dbo].[DataSources]  WITH CHECK ADD CONSTRAINT [FK_DataSources_DataCatalog] FOREIGN KEY([DataCatalog])
REFERENCES [dbo].[DataCatalog] ([Name])
GO

ALTER TABLE [dbo].[DataSources] CHECK CONSTRAINT [FK_DataSources_DataCatalog]
GO

/*
****** CREATE Table [dbo].[Participants] ******
*/


CREATE TABLE [dbo].[Participants](
	[Id] [uniqueidentifier] NOT NULL,
	[Name] [varchar](50) NOT NULL,
	[ClientId] [varchar](50) NOT NULL,
	[TenantId] [varchar](50) NOT NULL,
	[URL] [nvarchar](1024) NOT NULL,	
	[ClientSecret] [nvarchar](1024) NOT NULL,
	[IsEnabled] [bit] NOT NULL,
	[ValidFrom] [datetime2](7) NULL,
	[ValidTo] [datetime2](7) NULL,
	CONSTRAINT [PK_Participants_Name] PRIMARY KEY CLUSTERED 
	(
		[Name] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
	CONSTRAINT AK_Participants_ID UNIQUE([Id]) 
) ON [PRIMARY]

GO


/*
****** CREATE Table [dbo].[AvailableComputation] ******
*/


CREATE TABLE [dbo].[AvailableComputation](
	[Id] [uniqueidentifier] NOT NULL,
	[Name] [varchar](50) NOT NULL,
	[Description] [varchar](1024) NULL,		
	CONSTRAINT [PK_Computation_Name] PRIMARY KEY CLUSTERED 
	(
		[Name] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
	CONSTRAINT AK_Computation_ID UNIQUE([Id]) 
) ON [PRIMARY]

GO

/*
****** CREATE Table [dbo].[ComputationInfo] ******
*/


CREATE TABLE [dbo].[ComputationInfo](
	[Id] [uniqueidentifier] NOT NULL,
	[ProjectName] [varchar](50) NOT NULL,	
	[ProjectDescription] [varchar](1024) NULL,	
	[Formula] [varchar](max) NOT NULL,
	[DataCatalog] [varchar](50) NOT NULL,
	[ComputationType] [varchar](50) NOT NULL,
	[IsEnabled] [bit] NOT NULL,
	[ValidFrom] [datetime2](7) NULL,
	[ValidTo] [datetime2](7) NULL,
	CONSTRAINT [PK_ComputationInfo] PRIMARY KEY CLUSTERED 
	(
		[ProjectName] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
	CONSTRAINT AK_ComputationInfo_Id UNIQUE([Id]) 
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[ComputationInfo]  WITH CHECK ADD CONSTRAINT [FK_ComputationInfo_DataCatalog] FOREIGN KEY([DataCatalog])
REFERENCES [dbo].[DataCatalog] ([Name])
GO

ALTER TABLE [dbo].[ComputationInfo] CHECK CONSTRAINT [FK_ComputationInfo_DataCatalog]
GO

ALTER TABLE [dbo].[ComputationInfo]  WITH CHECK ADD CONSTRAINT [FK_ComputationInfo_ComputationType] FOREIGN KEY([ComputationType])
REFERENCES [dbo].[AvailableComputation] ([Name])
GO

ALTER TABLE [dbo].[ComputationInfo] CHECK CONSTRAINT [FK_ComputationInfo_ComputationType]
GO

/*
****** CREATE Table [dbo].[ComputationInfoParticipants] ******
*/

CREATE TABLE [dbo].[ComputationInfoParticipants](
	[Id] [uniqueidentifier] NOT NULL,
	[ComputationInfoName] [varchar](50) NOT NULL,	
	[ParticipantName] [varchar](50) NOT NULL,
	[IsEnabled] [bit] NOT NULL,
	CONSTRAINT [PK_ComputationInfoParticipants_1] PRIMARY KEY CLUSTERED 
	(
		[ComputationInfoName] ASC,	
		[ParticipantName] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
	CONSTRAINT AK_ComputationInfoParticipants_Id UNIQUE([Id]) 
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[ComputationInfoParticipants]  WITH CHECK ADD CONSTRAINT [FK_ComputationInfoParticipants_ComputationInfo] FOREIGN KEY([ComputationInfoName])
REFERENCES [dbo].[ComputationInfo] ([ProjectName])
GO

ALTER TABLE [dbo].[ComputationInfoParticipants] CHECK CONSTRAINT [FK_ComputationInfoParticipants_ComputationInfo]
GO

ALTER TABLE [dbo].[ComputationInfoParticipants]  WITH CHECK ADD CONSTRAINT [FK_ComputationInfoParticipants_Participant] FOREIGN KEY([ParticipantName])
REFERENCES [dbo].[Participants] ([Name])
GO

ALTER TABLE [dbo].[ComputationInfoParticipants] CHECK CONSTRAINT [FK_ComputationInfoParticipants_Participant]
GO

/*
****** CREATE Table [dbo].[ComputationInfoJob] ******
*/


CREATE TABLE [dbo].[ComputationInfoJob](
	[Id] [uniqueidentifier] NOT NULL,
	[ComputationInfo] [varchar](50) NOT NULL,
	[Operation] [varchar](50) NOT NULL,
	[Result] [varchar](max) NULL,
	[Summary] [varchar](max) NULL,
	[LogTxt] [varchar](max) NULL,
	[Status] [varchar](50) NULL,
	[StartDateTime] [datetime2](7) NOT NULL,
	[EndDateTime] [datetime2](7) NOT NULL,
	CONSTRAINT [PK_ComputationJob] PRIMARY KEY CLUSTERED 
	(
		[Id] ASC,
		[Operation] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
	
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO

ALTER TABLE [dbo].[ComputationInfoJob] ADD  CONSTRAINT [DF_ComputationJob_StartDateTime]  DEFAULT (getdate()) FOR [StartDateTime]
GO

ALTER TABLE [dbo].[ComputationInfoJob] ADD  CONSTRAINT [DF_ComputationJob_EndDateTime]  DEFAULT (getdate()) FOR [EndDateTime]
GO

ALTER TABLE [dbo].[ComputationInfoJob]  WITH CHECK ADD  CONSTRAINT [FK_ComputationJob_ComputationInfo] FOREIGN KEY([ComputationInfo])
REFERENCES [dbo].[ComputationInfo] ([ProjectName])
GO

ALTER TABLE [dbo].[ComputationInfoJob] CHECK CONSTRAINT [FK_ComputationJob_ComputationInfo]
GO
