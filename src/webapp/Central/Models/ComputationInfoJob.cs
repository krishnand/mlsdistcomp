using System;

namespace MRSDistCompWebApp.Models
{
    public class ComputationInfoJob
    {
        public string Id { get; set; }

        public string ComputationInfo { get; set; }

        public string Operation { get; set; }

        public string Result { get; set; }

        public string Summary { get; set; }

        public string LogTxt { get; set; }

        public string Status { get; set; }       
        
        public DateTime StartDateTime { get; set; }

        public DateTime EndDateTime { get; set; }
    }
}
